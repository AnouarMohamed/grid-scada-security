# AWS Cloud Handoff

This checklist separates repository work that is complete from account work
that requires the AWS owner. No repository automation applies cloud resources
without a manual workflow dispatch.

## Deployment Status

The default-off AWS foundation was applied in `us-east-1` and verified on
2026-09-12. Remote state, termination-protected bootstrap stacks, the cost
budget, anomaly monitoring, isolated routes, VPC flow logs, bounded workload
roles, four ECR repositories, and the ECS capacity providers are healthy. The
initial and remediated immutable image sets were published and verified on
2026-09-13; see the [initial publication record](deployment-records/2026-09-13-aws-image-publication.md)
and [remediated publication record](deployment-records/2026-09-13-aws-remediated-image-publication.md).
The retained GitHub OIDC plan role was deployed with immutable repository IDs
and produced a no-change remote plan on 2026-09-13; see the
[OIDC plan identity record](deployment-records/2026-09-13-aws-github-oidc-plan.md).
Runtime infrastructure and dormant services have since been created through
reviewed Terraform applies, while desired counts remain zero outside bounded
experiments. NAT, Elastic IPs, and public Grafana remain disabled. See the
[sanitized foundation deployment record](deployment-records/2026-09-12-aws-foundation.md).

## Complete In The Repository

- The local power simulator, Modbus ingestor, InfluxDB, and Grafana path runs
  end to end, including both attack replays and detector smoke tests.
- The AWS sandbox Terraform root models two availability zones with separate
  public-ingress, cloud-core, and isolated OT subnets.
- Security groups allow only the documented application paths; the ingestor is
  the sole service that initiates traffic into the OT simulation zone.
- Registry-level basic ECR scan-on-push for the GridGuard repository prefix and
  immutable tags, encrypted EFS, VPC flow logs, private AWS endpoints, Secrets
  Manager containers, and ECS deployment rollback are configured.
- Billable runtime resources, endpoints, NAT, and public Grafana are disabled
  by default. ECS desired counts also default to zero.
- Terraform formatting, validation, and mocked plan tests run in CI.
- Runtime bases and third-party CI actions are immutable, Python dependencies
  are audited, and built images are scanned before the required CI gate passes.
- `main` requires a current, passing `CI Gate` through a pull request and blocks
  force pushes and deletion.
- GitHub private vulnerability reporting is enabled and `SECURITY.md` points to
  that private channel.
- The protected `sandbox` environment can run metadata-only Terraform plans
  through short-lived OIDC credentials; the workflow and role cannot apply.

## AWS Owner Checklist

Perform these steps in order and stop whenever the reviewed plan differs from
the expected scope.

1. Use a dedicated non-production AWS account. Protect root and the bootstrap
   identity with MFA, remove root and IAM access keys, and configure a strong
   account password policy. Use browser-issued temporary CLI credentials.
2. Configure a monthly AWS cost budget and billing alerts before creating
   infrastructure. Select **Unblended cost** in the current console so the
   budget does not net promotional credits. For a legacy API budget, set
   `CostTypes.IncludeCredit` to `false`.
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
5. Validate and review the retained, versioned, KMS-encrypted,
   public-access-blocked [state-backend bootstrap](../infra/cloudformation/bootstrap/README.md).
   An account owner creates its CloudFormation change set and grants the
   bootstrap identity exact-object access to the state and `.tflock` objects.
6. Copy `backend.tfbackend.example` to the ignored `backend.tfbackend`, and
   `terraform.tfvars.example` to the ignored `terraform.tfvars`. Replace every
   placeholder and keep all runtime flags disabled.
7. Create and review the MFA-gated
   [foundation deployment role](../infra/cloudformation/bootstrap/foundation-deployment-role.md).
   Use its workload-boundary output in `terraform.tfvars`; never apply as root
   or attach `AdministratorAccess` to the operator.
8. Run `terraform init -backend-config=backend.tfbackend`,
   `terraform validate`, `terraform test`, and a saved foundation plan. Inspect
   account, region, CIDRs, resource count, tags, and
   `estimated_billable_features` before applying.
9. Apply only the reviewed foundation plan. Record the ECR URLs and confirm the
   OT route tables have no default internet or NAT route.
10. Build and scan all four images from the repository Dockerfiles. Tag and push
   them with the exact non-`latest` versions in `image_tags`; ECR tags cannot be
   overwritten. Record each ECR image digest in the change record.
11. Validate and review the retained
   [GitHub OIDC plan-role bootstrap](../infra/cloudformation/bootstrap/github-oidc-plan-role.md).
   An account owner creates its change set. It must contain exactly one OIDC
   provider, one plan-only managed policy, and one plan-only role, all as
   additions. This role cannot apply Terraform.
12. Put `AWS_ROLE_TO_ASSUME`, `AWS_REGION`, `TF_STATE_BUCKET`, and
   `TF_STATE_KMS_KEY_ARN` in the `sandbox` GitHub environment. Restrict the
   environment to protected branches and run the manual plan workflow. Use
   `TF_STATE_KEY` only to override the documented default, and `TF_VARS_JSON`
   only for reviewed, non-secret variable overrides.
13. Enable runtime and VPC endpoints with every desired count still zero. Apply
   the reviewed plan to create storage, secret containers, task definitions,
   and dormant services.
14. Populate the two secret values directly through Secrets Manager. Never put
   secret values in Terraform variables, plans, logs, or state.
15. Raise InfluxDB and Grafana to one task first, validate storage and health,
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

ECS task definitions are pinned to verified runnable image digests, signed SBOM
evidence is complete, and the remaining InfluxDB findings have a conditional,
exact-digest [risk acceptance](deployment-records/2026-09-19-influxdb-runtime-risk-acceptance.md).
The next action is one supervised, maximum-eight-hour exercise under those
conditions, using the [runtime evidence runbook](13-aws-runtime-evidence.md),
followed immediately by a zero-task teardown and cost review.
