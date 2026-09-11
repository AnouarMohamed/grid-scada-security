# AWS Sandbox Environment

This root maps the local GridGuard lab to AWS without flattening the OT/cloud
boundary. It is safe by default: `enable_runtime = false` creates the network,
flow logs, security groups, ECR repositories, ECS cluster, and IAM task roles,
but it does not create tasks, an ALB, EFS filesystems, interface endpoints, or
Secrets Manager secrets.

No command in CI automatically applies this environment.

## Architecture

Two availability zones each receive three subnets:

- `public-ingress`: optional public HTTPS ALB and NAT gateway only.
- `cloud-core`: Modbus ingestion, InfluxDB, Grafana, EFS mount targets, and
private AWS endpoints. The optional NAT path permits HTTPS only from cloud-side
tasks; it never adds an OT route or OT task egress.
- `ot-sim`: isolated power simulator tasks with no internet or NAT route.

Security groups enforce these application paths:

```text
operator CIDRs -> Grafana ALB -> Grafana -> InfluxDB

Modbus ingestor -> power-sim:502
Modbus ingestor -> InfluxDB:8086
tasks -> private AWS endpoints:443 and S3 prefix list:443
InfluxDB/Grafana -> EFS:2049
```

The ingestor is the only application service that can initiate traffic across
the modeled OT/cloud boundary. VPC flow logs capture accepted and rejected
traffic.

## Cost Gates

Review current AWS pricing before changing feature flags. The default plan
avoids the largest recurring resources, but flow-log ingestion and any images
stored in ECR remain usage-based costs. Enabling runtime creates four Fargate
services, an ALB, two encrypted EFS filesystems with automatic backups, a Cloud
Map namespace, two secrets, and four interface VPC endpoints across two AZs. A
NAT gateway is separate and remains disabled by default; OT subnets never
receive a NAT route.

Terraform outputs `estimated_billable_features` so every plan records which
cost-bearing groups are enabled. AWS budgets and account-level cost alerts are
still recommended before the first apply.

## Prerequisites

- Terraform `1.10` or newer (required for native S3 state lockfiles).
- AWS CLI v2 authenticated to a dedicated sandbox account.
- Docker, `jq`, and an image scanner such as Trivy for the image-publish phase.
- Permission to manage VPC, ECS, ECR, EFS, ELB, Cloud Map, CloudWatch Logs,
  AWS Backup, Secrets Manager, and the explicitly named IAM and service-linked
  roles.
- Two available AZs in the chosen region.

## Phase 1: Foundation

Create a versioned, encrypted S3 bucket with public access blocked before the
first plan. Copy `backend.tfbackend.example` to the ignored
`backend.tfbackend`, replace its bucket and region, and initialize the committed
partial S3 backend. Terraform's S3 lockfile is enabled; the IAM principal needs
S3 access to both the state object and its `.tflock` object.

```bash
cd infra/terraform/environments/aws-sandbox
cp backend.tfbackend.example backend.tfbackend
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.tfbackend
terraform fmt -check
terraform validate
terraform test
terraform plan -out=foundation.tfplan
terraform show foundation.tfplan
```

Confirm that `enable_runtime`, `enable_vpc_endpoints`, and
`enable_nat_gateway` are all `false` before applying the foundation.

```bash
terraform apply foundation.tfplan
```

## Build And Push Images

The foundation output contains each ECR URL. Authenticate Docker, then build,
tag, scan, and push immutable release tags. The InfluxDB image is intentionally
mirrored into private ECR so isolated tasks never pull from Docker Hub.

```bash
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

docker build -f power-sim/Dockerfile -t gridguard-power-sim .
docker build -f infra/services/modbus-ingestor/Dockerfile -t gridguard-modbus-ingestor .
docker build -f infra/images/grafana/Dockerfile -t gridguard-grafana .
docker build -f infra/images/influxdb/Dockerfile -t gridguard-influxdb .

trivy image --exit-code 1 --severity HIGH,CRITICAL gridguard-power-sim
trivy image --exit-code 1 --severity HIGH,CRITICAL gridguard-modbus-ingestor
trivy image --exit-code 1 --severity HIGH,CRITICAL gridguard-grafana
trivy image --exit-code 1 --severity HIGH,CRITICAL gridguard-influxdb
```

Scan the four local images before publishing. Then use the foundation outputs
to tag and push versions that match `image_tags`:

```bash
POWER_SIM_REPO="$(terraform output -json ecr_repository_urls | jq -r '."power-sim"')"
INGESTOR_REPO="$(terraform output -json ecr_repository_urls | jq -r '."modbus-ingestor"')"
INFLUXDB_REPO="$(terraform output -json ecr_repository_urls | jq -r '.influxdb')"
GRAFANA_REPO="$(terraform output -json ecr_repository_urls | jq -r '.grafana')"

docker tag gridguard-power-sim "${POWER_SIM_REPO}:0.1.0"
docker tag gridguard-modbus-ingestor "${INGESTOR_REPO}:0.1.0"
docker tag gridguard-influxdb "${INFLUXDB_REPO}:2.9.0"
docker tag gridguard-grafana "${GRAFANA_REPO}:12.4.10"

docker push "${POWER_SIM_REPO}:0.1.0"
docker push "${INGESTOR_REPO}:0.1.0"
docker push "${INFLUXDB_REPO}:2.9.0"
docker push "${GRAFANA_REPO}:12.4.10"
```

ECR tag mutability is disabled, so publish a new version instead of replacing a
tag. Update `terraform.tfvars` and review a new plan whenever a version changes.

## Runtime Secrets

Set `enable_runtime = true` and `enable_vpc_endpoints = true`, keep all desired
counts at zero, and apply a separately reviewed runtime-foundation plan:

```bash
terraform plan -out=runtime-zero.tfplan
terraform show runtime-zero.tfplan
terraform apply runtime-zero.tfplan
```

Populate the new secret containers outside Terraform so no credential enters
configuration or state:

```bash
aws secretsmanager put-secret-value \
  --secret-id gridguard-aws-sandbox/influxdb \
  --secret-string file://influxdb-secret.json

aws secretsmanager put-secret-value \
  --secret-id gridguard-aws-sandbox/grafana \
  --secret-string file://grafana-secret.json
```

`influxdb-secret.json` must contain `username`, `password`, and `token`.
`grafana-secret.json` must contain `username` and `password`. Keep these files
outside the repository and delete them securely after upload.

ECS desired counts default to zero. Keep them there for the first runtime plan,
populate secrets, confirm all four images exist in ECR, and then raise the
counts to one in a second reviewed plan. Stateful InfluxDB and Grafana services
are capped at one task to prevent unsupported multi-writer access to EFS.

## GitHub OIDC Bootstrap

The OIDC provider is account-wide. Check for an existing provider before using
`create_github_oidc_provider = true`. Otherwise pass its ARN through
`github_oidc_provider_arn`.

The role trusts only this repository and the listed GitHub environments, with
audience `sts.amazonaws.com`. It deliberately receives no AWS permissions
unless `github_deploy_policy_arn` names an account-managed policy. Use a
permissions boundary through `github_role_permissions_boundary_arn` where your
account supports one.

The repository intentionally does not provide a generic administrator policy.
Build the account-managed policy around the selected state bucket and the
planned GridGuard resource names, review it with IAM Access Analyzer, and never
attach `AdministratorAccess` to the deployment role.

After bootstrap, place the `github_deploy_role_arn` output in the selected
GitHub environment as `AWS_ROLE_TO_ASSUME`, and set `AWS_REGION` as an
environment variable. Set `TF_STATE_BUCKET`; optionally override
`TF_STATE_KEY`, whose default is `gridguard/aws-sandbox/terraform.tfstate`.

The deployment workflow uses Terraform defaults unless the environment variable
`TF_VARS_JSON` contains a valid non-secret JSON object of variable overrides.
Keep credentials out of this object. A sandbox runtime example is:

```json
{
  "enable_runtime": true,
  "enable_vpc_endpoints": true,
  "desired_counts": {
    "power_sim": 0,
    "modbus_ingestor": 0,
    "influxdb": 0,
    "grafana": 0
  }
}
```

## Grafana Exposure

Grafana is internal by default. Reach it through a private connectivity path
such as a VPN or a controlled operator network whose CIDR is listed in
`operator_cidrs`.

Setting `grafana_public = true` moves the ALB to public subnets and is rejected
unless `grafana_certificate_arn` is provided. Restrict `operator_cidrs` to known
operator addresses; do not use `0.0.0.0/0`.

## Destruction

ECR repositories use `force_delete = false`, and Secrets Manager uses a
seven-day recovery window. Empty repositories before destroy. Export any
required telemetry before destroying EFS. Always inspect a destroy plan:

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
```
