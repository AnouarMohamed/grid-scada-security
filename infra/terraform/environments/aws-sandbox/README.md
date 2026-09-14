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

### Us-east-1 Cost Envelope

The following estimate was checked against AWS public pricing on 2026-09-11
and assumes 730 hours per month. It excludes traffic, log ingestion, image and
filesystem storage, backups, taxes, and promotional credits. Recalculate it
before every runtime deployment because prices and Free Tier eligibility can
change.

| Configuration | Approximate fixed monthly cost | Main components |
| --- | ---: | --- |
| Foundation defaults | ~$1 | One customer-managed state-encryption KMS key: $1; VPC, subnets, route tables, security groups, IAM roles, ECS cluster, and empty ECR repositories have no fixed hourly charge; flow logs, ECR, S3 state, and KMS requests remain usage-based. |
| Runtime created, task counts zero | ~$77.13 | Foundation plus eight interface-endpoint ENIs: $58.40; one ALB: $16.43; two secrets: $0.80; one private DNS namespace: $0.50. |
| Four tasks continuously running | ~$158.62 | Runtime-zero resources plus approximately $81.09 of Linux/x86 Fargate compute for 2.25 vCPU and 4.5 GB total memory, and $0.40 for four Cloud Map registrations. |
| Optional NAT gateway | +~$36.50 | One NAT gateway: $32.85; one public IPv4 address: $3.65; data processing and transfer are additional. |

The endpoint estimate uses four interface services in two AZs at $0.01 per
endpoint ENI-hour. Fargate uses $0.000011244 per vCPU-second and $0.000001235
per GB-second. The ALB base charge is $0.0225 per hour before LCUs. See the
official [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/),
[Fargate pricing](https://aws.amazon.com/ecs/pricing/),
[load-balancer pricing](https://aws.amazon.com/elasticloadbalancing/pricing/),
[Secrets Manager pricing](https://aws.amazon.com/secrets-manager/pricing/), and
[Cloud Map pricing](https://aws.amazon.com/cloud-map/pricing/). The state-key
estimate uses the official [KMS pricing](https://aws.amazon.com/kms/pricing/);
completed automatic rotations can increase its monthly storage charge.

Do not leave runtime resources enabled under a $20 monthly budget. Use the
foundation configuration for persistent study, and create the runtime only for
a supervised exercise with the same-day destroy procedure already reviewed.
Create and inspect the destroy plan immediately after the exercise. An
eight-hour runtime window is approximately $1.72 in exercise-specific fixed
compute, endpoint, ALB, and secret charges, plus the persistent state key and
usage-based charges; a DNS hosted-zone charge can also apply unless AWS's
short-lived-zone exception applies.

## Prerequisites

- Terraform `1.10` or newer (required for native S3 state lockfiles).
- AWS CLI v2 authenticated to a dedicated sandbox account.
- Docker, `jq`, and an image scanner such as Trivy for the image-publish phase.
- Permission to manage VPC, ECS, ECR, EFS, ELB, Cloud Map, CloudWatch Logs,
  AWS Backup, Secrets Manager, and the explicitly named IAM and service-linked
  roles.
- Two available AZs in the chosen region.

## Account Preflight

Before creating the state bucket or granting write permissions, run the
repository's read-only account audit with a non-root profile:

```bash
AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
AWS_REGION="us-east-1" \
AWS_AUDIT_ALL_REGIONS="true" \
make aws-preflight
```

The audit rejects root sessions, missing MFA, long-lived access keys, a weak or
missing IAM password policy, inactive Free plans, budgets that net promotional
credits, and regions with fewer than two available zones. Current budgets must
use the **Unblended cost** metric; legacy API budgets must set
`CostTypes.IncludeCredit` to `false`. The audit reports existing resources
without modifying them. `AWS_BUDGET_NAME` defaults to
`gridguard-gross-usage` and can be overridden for another sandbox.

Resolve every `FAIL` before creating infrastructure. Review every `WARN` and
confirm that the reported resources are intentional. Read-only permissions are
sufficient for this phase; do not attach administrator access merely to run the
audit.

## Phase 1: Foundation

Create the versioned, customer-managed-KMS-encrypted S3 bucket with public
access blocked before the first plan. Use the reviewed
[state-backend bootstrap](../../../cloudformation/bootstrap/README.md). Copy
`backend.tfbackend.example` to the ignored `backend.tfbackend`, replace its
bucket, KMS key ARN, and region, and initialize the committed partial S3
backend. Terraform's S3 lockfile is enabled; the IAM principal needs S3 access
to both the state object and its `.tflock` object plus use of the KMS key.

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

for image in \
  gridguard-power-sim \
  gridguard-modbus-ingestor \
  gridguard-grafana \
  gridguard-influxdb; do
  trivy image --exit-code 0 --ignore-unfixed --scanners vuln \
    --severity HIGH,CRITICAL "$image"
  trivy image --exit-code 1 --scanners vuln \
    --severity CRITICAL "$image"
done
```

The reporting pass focuses on actionable high and critical findings. The gate
includes findings without a vendor fix and rejects any known critical finding.
Scan the four local images before publishing. Then use the foundation outputs
to tag and push versions that match `image_tags`:

```bash
POWER_SIM_REPO="$(terraform output -json ecr_repository_urls | jq -r '."power-sim"')"
INGESTOR_REPO="$(terraform output -json ecr_repository_urls | jq -r '."modbus-ingestor"')"
INFLUXDB_REPO="$(terraform output -json ecr_repository_urls | jq -r '.influxdb')"
GRAFANA_REPO="$(terraform output -json ecr_repository_urls | jq -r '.grafana')"

docker tag gridguard-power-sim "${POWER_SIM_REPO}:0.1.1"
docker tag gridguard-modbus-ingestor "${INGESTOR_REPO}:0.1.1"
docker tag gridguard-influxdb "${INFLUXDB_REPO}:2.9.1-gridguard.2"
docker tag gridguard-grafana "${GRAFANA_REPO}:12.4.10-gridguard.1"

docker push "${POWER_SIM_REPO}:0.1.1"
docker push "${INGESTOR_REPO}:0.1.1"
docker push "${INFLUXDB_REPO}:2.9.1-gridguard.2"
docker push "${GRAFANA_REPO}:12.4.10-gridguard.1"
```

ECR tag mutability is disabled, so publish a new version instead of replacing a
tag. Resolve each OCI index to its scanned Linux/AMD64 manifest, then update
`image_tags` and `image_digests` together. ECS task definitions use
`repository@sha256:...`, so changing a tag cannot change deployed bytes. Review
a new plan whenever either release map changes.

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

For this account, create the OIDC provider and plan-only role with the retained
[CloudFormation bootstrap](../../../cloudformation/bootstrap/github-oidc-plan-role.md).
Keep `create_github_oidc_provider = false`, `github_oidc_provider_arn = null`,
and `github_deploy_policy_arn = null` in this Terraform root. Those variables
remain a reusable alternative for accounts that deliberately choose Terraform
ownership, but mixing both ownership paths would create drift.

The bootstrap role trusts only this repository's immutable owner/repository ID
prefix, exact `sandbox` environment, and audience `sts.amazonaws.com`. Verify
the current prefix through GitHub's repository OIDC settings API before every
trust update. Its policy is also its permissions boundary. It can read the
exact Terraform state object, manage the exact lock object, use the state KMS
key, and read resource metadata. It cannot write state, retrieve secret values,
pass roles, or apply infrastructure changes.

After bootstrap, place its `GitHubPlanRoleArn` output in the `sandbox` GitHub
environment as `AWS_ROLE_TO_ASSUME`. Set `AWS_REGION`, `TF_STATE_BUCKET`, and
`TF_STATE_KMS_KEY_ARN` as environment variables. Optionally override
`TF_STATE_KEY`, whose default is `gridguard/aws-sandbox/terraform.tfstate`.

The plan workflow uses Terraform defaults unless the environment variable
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

The committed workflow has no apply input or apply step. Treat any future apply
role as a separate privileged system: define a resource-scoped policy, validate
it independently, require environment approval, and review the workflow change
through the protected branch before granting access.

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
