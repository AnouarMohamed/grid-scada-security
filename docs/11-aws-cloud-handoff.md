# AWS Cloud Handoff

This checklist separates repository work that is complete from account work
that requires the AWS owner. No repository automation applies cloud resources
without a manual workflow dispatch.

## Complete In The Repository

- The local power simulator, Modbus ingestor, InfluxDB, and Grafana path runs
  end to end, including both attack replays and detector smoke tests.
- The AWS sandbox Terraform root models two availability zones with separate
  public-ingress, cloud-core, and isolated OT subnets.
- Security groups allow only the documented application paths; the ingestor is
  the sole service that initiates traffic into the OT simulation zone.
- ECR scanning and immutable tags, encrypted EFS, VPC flow logs, private AWS
  endpoints, Secrets Manager containers, and ECS deployment rollback are
  configured.
- Billable runtime resources, endpoints, NAT, public Grafana, and GitHub OIDC
  are disabled by default. ECS desired counts also default to zero.
- Terraform formatting, validation, and mocked plan tests run in CI.
- `main` requires a current, passing `CI Gate` through a pull request and blocks
  force pushes and deletion.
- GitHub private vulnerability reporting is enabled and `SECURITY.md` points to
  that private channel.

## AWS Owner Checklist

Perform these steps in order and stop whenever the reviewed plan differs from
the expected scope.

1. Use a dedicated non-production AWS account and configure an AWS Budget plus
   billing alerts before creating infrastructure.
2. Select one AWS region and two available zones. Confirm service quotas for
   VPC, elastic IPs, ECS/Fargate, ECR, EFS, ALB, Cloud Map, and interface
   endpoints.
3. Create a versioned, encrypted, public-access-blocked S3 state bucket. Grant
   the bootstrap identity access to the state object and its `.tflock` object.
4. Copy `backend.tfbackend.example` to the ignored `backend.tfbackend`, and
   `terraform.tfvars.example` to the ignored `terraform.tfvars`. Replace every
   placeholder and keep all runtime flags disabled.
5. Run `terraform init -backend-config=backend.tfbackend`,
   `terraform validate`, `terraform test`, and a saved foundation plan. Inspect
   account, region, CIDRs, resource count, tags, and
   `estimated_billable_features` before applying.
6. Apply only the reviewed foundation plan. Record the ECR URLs and confirm the
   OT route tables have no default internet or NAT route.
7. Build, scan, tag, and push all four images with unique non-`latest` versions.
   ECR tags cannot be overwritten.
8. Bootstrap or reference the account-wide GitHub OIDC provider. Create a
   least-privilege account-managed deployment policy, review it separately,
   and attach it through `github_deploy_policy_arn` only when ready.
9. Put `AWS_ROLE_TO_ASSUME`, `AWS_REGION`, and `TF_STATE_BUCKET` in the
   `sandbox` GitHub environment. Add an environment approval rule before
   enabling apply. Use `TF_STATE_KEY` only to override the documented default,
   and `TF_VARS_JSON` only for reviewed, non-secret variable overrides.
10. Enable runtime and VPC endpoints with every desired count still zero. Apply
    the reviewed plan to create storage, secret containers, task definitions,
    and dormant services.
11. Populate the two secret values directly through Secrets Manager. Never put
    secret values in Terraform variables, plans, logs, or state.
12. Raise InfluxDB and Grafana to one task first, validate storage and health,
    then raise the simulator and ingestor. Confirm flow logs and dashboards
    before running attack scenarios.

## Required Decisions

The AWS owner must choose the account, region, AZs, state-bucket name,
operator CIDRs, ACM certificate and private-access path for Grafana, image
versions, secrets, budget thresholds, deployment policy, permissions boundary,
and environment approval rules.

The exact commands, secret JSON fields, cost gates, OIDC behavior, and destroy
procedure are documented in the
[AWS sandbox runbook](../infra/terraform/environments/aws-sandbox/README.md).

## Next

The next action is an account-side review of the foundation plan with every
billable runtime flag disabled. Do not enable runtime until the state backend,
budget alerts, ECR images, private access path, and secret-handling procedure
are all ready.
