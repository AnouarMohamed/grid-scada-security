# Terraform Skeleton

This directory defines the infrastructure contract for the DevSecOps track.
It is intentionally provider-light right now: the local fake-data pipeline runs
with Docker Compose, while Terraform captures the cloud shape we must preserve
when AWS resources are added.

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
Terraform CLI is not installed.

## Next Cloud Step

When the team is ready for AWS, add a new environment under
`infra/terraform/environments/aws-sandbox/` and map the existing module
contracts to concrete resources:

- VPC and segmented subnets.
- Security groups that enforce the OT/cloud boundary.
- ECS/Fargate or a small Kubernetes target for services.
- Managed database or persistent volume strategy.
- IAM roles wired to GitHub OIDC.
