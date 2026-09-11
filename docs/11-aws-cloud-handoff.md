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
- Runtime bases and third-party CI actions are immutable, Python dependencies
  are audited, and built images are scanned before the required CI gate passes.
- `main` requires a current, passing `CI Gate` through a pull request and blocks
  force pushes and deletion.
- GitHub private vulnerability reporting is enabled and `SECURITY.md` points to
  that private channel.

## AWS Owner Checklist

Perform these steps in order and stop whenever the reviewed plan differs from
the expected scope.

1. Use a dedicated non-production AWS account. Protect root and the bootstrap
   identity with MFA, remove root and IAM access keys, and configure a strong
   account password policy. Use browser-issued temporary CLI credentials.
2. Configure a monthly AWS cost budget and billing alerts before creating
   infrastructure. Set `CostTypes.IncludeCredit` to `false` so the budget
   measures gross usage instead of hiding usage behind promotional credits.
3. Attach read-only service and billing permissions to the bootstrap identity,
   authenticate a non-root CLI profile, and run the read-only preflight. Resolve
   every failure before granting deployment permissions:

   ```bash
   AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
   AWS_REGION="us-east-1" \
   AWS_AUDIT_ALL_REGIONS="true" \
   make aws-preflight
   ```

   The command masks the account number, never reads secret values, and makes
   only read-only get, list, describe, and identity calls.
4. Select one AWS region and two available zones. Confirm service quotas for
   VPC, elastic IPs, ECS/Fargate, ECR, EFS, ALB, Cloud Map, and interface
   endpoints.
5. Create a versioned, encrypted, public-access-blocked S3 state bucket. Grant
   the bootstrap identity access to the state object and its `.tflock` object.
6. Copy `backend.tfbackend.example` to the ignored `backend.tfbackend`, and
   `terraform.tfvars.example` to the ignored `terraform.tfvars`. Replace every
   placeholder and keep all runtime flags disabled.
7. Run `terraform init -backend-config=backend.tfbackend`,
   `terraform validate`, `terraform test`, and a saved foundation plan. Inspect
   account, region, CIDRs, resource count, tags, and
   `estimated_billable_features` before applying.
8. Apply only the reviewed foundation plan. Record the ECR URLs and confirm the
   OT route tables have no default internet or NAT route.
9. Build and scan all four images from the repository Dockerfiles. Tag and push
   them with the exact non-`latest` versions in `image_tags`; ECR tags cannot be
   overwritten. Record each ECR image digest in the change record.
10. Bootstrap or reference the account-wide GitHub OIDC provider. Create a
   least-privilege account-managed deployment policy, review it separately,
   and attach it through `github_deploy_policy_arn` only when ready.
11. Put `AWS_ROLE_TO_ASSUME`, `AWS_REGION`, and `TF_STATE_BUCKET` in the
   `sandbox` GitHub environment. Add an environment approval rule before
   enabling apply. Use `TF_STATE_KEY` only to override the documented default,
   and `TF_VARS_JSON` only for reviewed, non-secret variable overrides.
12. Enable runtime and VPC endpoints with every desired count still zero. Apply
    the reviewed plan to create storage, secret containers, task definitions,
    and dormant services.
13. Populate the two secret values directly through Secrets Manager. Never put
    secret values in Terraform variables, plans, logs, or state.
14. Raise InfluxDB and Grafana to one task first, validate storage and health,
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
