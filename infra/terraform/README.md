# Terraform Environments

This directory defines the infrastructure contract for the DevSecOps track.
The provider-light local environment documents the Compose boundary, while the
AWS sandbox root maps that boundary to deployable provider resources.

The important early decisions are already represented:

- The OT simulation zone and cloud telemetry zone are separate.
- The telemetry ingestor is the only dual-homed boundary service.
- Observability services have explicit exposure rules.
- Outputs are structured so CI/CD and future deployment scripts can consume
  environment metadata without scraping prose.

## Layout

```text
infra/terraform/
├── environments/
│   ├── aws-sandbox/
│   └── local-dev/
└── modules/
    ├── network-boundary/
    └── observability-foundation/
```

## Validate

```bash
make terraform
```

In GitHub Actions, Terraform is installed by the workflow and validation is
strict. Locally, the validation script will skip Terraform checks if the
Terraform CLI is not installed. Environment roots with a `tests/` directory
also run `terraform test` through the same command.

## AWS Sandbox

The [AWS sandbox runbook](environments/aws-sandbox/README.md) accounts for:

- Two-AZ public ingress, private cloud, and isolated OT subnets.
- Explicit security-group paths across the OT/cloud boundary.
- ECS/Fargate services, private ECR, encrypted EFS, and private AWS endpoints.
- Secrets Manager containers whose values remain outside Terraform state.
- A tightly scoped GitHub OIDC trust role with no permissions by default.
- Cost-bearing runtime features disabled by default.

The repository supplies and validates this configuration but does not apply it.
The separate [CloudFormation state bootstrap](../cloudformation/bootstrap/README.md)
creates the backend without a Terraform state dependency. Account bootstrap,
secrets, policy authorization, cost controls, and final AWS applies remain
deliberate operator actions.
