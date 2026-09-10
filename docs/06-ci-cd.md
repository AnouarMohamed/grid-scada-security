# CI/CD Pipeline

This pipeline is the integration safety net for GridGuard. It starts useful
while the repository is still mostly documentation, then tightens as the
Power Systems and DevSecOps tracks add source code, infrastructure, containers,
and cloud deployment targets.

## Path

1. **Now: foundation gates**
   - Repository hygiene: line endings, final newlines, trailing whitespace,
     root-level secret ignore rules.
   - Documentation validation: Markdown files must have balanced fenced code
     blocks and valid relative links.
   - Security scanning: committed-secret scanning with Gitleaks and filesystem
     vulnerability/IaC scanning with Trivy.

2. **Power track code lands**
   - Python CI automatically runs when `*.py` files exist.
   - The gate installs requirements files, runs Ruff, runs Bandit SAST, and
     runs pytest once tests exist.
   - Expected source surface: `power-sim/`.

3. **DevSecOps track code lands**
   - Terraform CI automatically runs when `*.tf` or `*.tf.json` files exist.
   - The gate runs `terraform fmt`, `terraform init -backend=false`, and
     `terraform validate` for each root.
   - Roots with a `tests/` directory also run `terraform test` with mocked
     providers, so CI does not contact or mutate a cloud account.
   - Expected source surface: `infra/`.

4. **Containers and local integration land**
   - Docker CI automatically validates Compose files and builds Dockerfiles in
     GitHub Actions.
   - Local `make docker` validates Compose by default; set
     `GRIDGUARD_DOCKER_BUILD=1` to build images locally.
   - The fake-data pipeline can be smoke-tested with `make stack-smoke` after
     `make stack-up`.

5. **Cloud deployment**
   - Deployment is manual through `.github/workflows/deploy.yml`.
   - `plan` is the default action.
   - The operator selects exactly one allow-listed root: `aws-sandbox` or
     `local-dev`.
   - `apply` is guarded to `main`; AWS actions require an OIDC role.
   - GitHub environments should require approval before real cloud credentials
     are configured.

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

- Python coverage thresholds for simulation, Modbus, ingestion, and detection
  logic.
- Terraform plan artifacts on pull requests once cloud resources exist.
- Docker image SBOM generation and signed image publishing.
- A staging environment that deploys from `main` before production.
- End-to-end attack-run smoke tests using the attack log template.
