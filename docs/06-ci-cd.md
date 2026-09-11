# CI/CD Pipeline

This pipeline is the integration safety net for GridGuard. It starts useful
while the repository is still mostly documentation, then tightens as the
Power Systems and DevSecOps tracks add source code, infrastructure, containers,
and cloud deployment targets.

## Path

1. **Now: foundation gates**
   - Repository hygiene: line endings, final newlines, trailing whitespace,
     secret ignore rules, ignored tracked files, and a 5 MiB tracked-file cap.
   - Documentation validation: Markdown files must have balanced fenced code
     blocks and valid relative links.
   - Security scanning: committed-secret scanning with Gitleaks and filesystem
     vulnerability/IaC scanning with Trivy.

2. **Power track code lands**
   - Python CI automatically runs when `*.py` files exist.
   - The gate installs pinned development tools, runs Ruff and Bandit SAST,
     audits every requirements file with pip-audit, and runs pytest on both
     container runtime versions (Python 3.12 and 3.14) with an 80% aggregate
     coverage floor.
   - Workflow policy runs actionlint and yamllint, requires full commit SHAs
     for third-party actions, requires explicit top-level permissions, and
     prohibits `pull_request_target`.
   - Expected source surface: `power-sim/`.

3. **DevSecOps track code lands**
   - Terraform CI automatically runs when `*.tf` or `*.tf.json` files exist.
   - The gate runs `terraform fmt`, `terraform init -backend=false`, and
     `terraform validate` for each root.
   - Roots with a `tests/` directory also run `terraform test` with mocked
     providers, so CI does not contact or mutate a cloud account.
   - Expected source surface: `infra/`.

4. **Containers and local integration land**
   - Docker CI validates Compose, builds every Dockerfile, reports fixed high
     and critical findings, and blocks fixed critical image vulnerabilities.
   - Every Dockerfile base and default stateful Compose image uses a complete
     multi-platform digest. Dependabot proposes reviewed digest updates.
   - Local `make docker` validates Compose by default; set
     `GRIDGUARD_DOCKER_BUILD=1` to build images locally.
   - The fake-data pipeline can be smoke-tested with `make stack-smoke` after
     `make stack-up`.

5. **Cloud deployment**
   - Deployment is manual through `.github/workflows/deploy.yml`.
   - `plan` is the default action.
   - The workflow is fixed to `infra/terraform/environments/aws-sandbox` and
     the `sandbox` GitHub environment. Local metadata is validated in CI and is
     never a cloud deployment target.
   - `apply` is guarded to `main`; every run requires an OIDC role and durable,
     encrypted remote state.
   - The `sandbox` environment should require approval before real cloud
     credentials are configured.

## Branch Protection

Use `CI Gate` as the required status check on `main`. The individual jobs stay
visible for debugging, but one required gate keeps branch protection simple.

Current `main` settings:

- Require a pull request before merging into `main`.
- Require the strict `CI Gate` check before merging.
- Enforce protection for administrators.
- Require review conversations to be resolved.
- Block force pushes and branch deletion.
- Require zero approvals while there is one maintainer; raise this to at least
  one when another maintainer joins.

## Secrets And Cloud Identity

Use GitHub OIDC for cloud authentication. Do not store static cloud access keys
in repository secrets.

For AWS, configure these values on the target GitHub environment:

- Environment variable: `AWS_REGION`
- Secret: `AWS_ROLE_TO_ASSUME`
- Environment variable: `TF_STATE_BUCKET`
- Optional environment variable: `TF_STATE_KEY`
- Optional non-secret JSON variable object: `TF_VARS_JSON`

The AWS role should trust this repository through GitHub's OIDC provider and
should be scoped to the exact Terraform state/backend and runtime resources
needed by the target environment.

The deploy workflow requires the remote state bucket for every AWS plan and
apply. It validates `TF_VARS_JSON` as an object and writes it only to the
ephemeral runner; Terraform secrets must still be populated directly in
Secrets Manager, never passed through that object.

The AWS Terraform root can create the constrained trust role, but attaches no
deployment permissions unless an account-managed policy ARN is explicitly
provided. See the [AWS cloud handoff](11-aws-cloud-handoff.md) before enabling
the workflow.

## Local Commands

Run all local gates:

```bash
make ci
```

Run a focused gate:

```bash
make docs
make python
make workflows
make modbus-contracts
make terraform
make docker
```

Run the local fake-data stack:

```bash
make stack-up
make stack-smoke
make stack-down
```

Run the receiver-side Modbus contract fixture:

```bash
make stack-modbus-up
make stack-modbus-smoke
make stack-down
```

## Future Hardening

Add these once the corresponding project surfaces exist:

- Terraform plan artifacts on pull requests once cloud resources exist.
- Docker image SBOM generation and signed image publishing.
- A staging environment that deploys from `main` before production.
- Raise the Python coverage floor as orchestration code gains deterministic
  unit seams; decreases require an explicit review.
