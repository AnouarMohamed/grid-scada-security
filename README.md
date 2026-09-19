# GridGuard: Cloud-Native SCADA Security Lab

[![CI](https://github.com/AnouarMohamed/grid-scada-security/actions/workflows/ci.yml/badge.svg)](https://github.com/AnouarMohamed/grid-scada-security/actions/workflows/ci.yml)

GridGuard is a secure digital-twin lab for a power distribution grid. The
project joins power-system simulation with DevSecOps infrastructure so the team
can generate realistic SCADA-style telemetry, move it across a deliberately
modeled OT/IT boundary, attack it, detect it, and document the full red/blue
exercise.

The goal is not just to build a demo. The goal is to create a reproducible
integration environment where every major piece can be rebuilt, tested, scanned,
and defended with the same discipline expected from critical-infrastructure
software.

## What This Project Builds

GridGuard models a distribution feeder, exposes live measurements over an
industrial protocol, ingests those measurements into a cloud-native telemetry
pipeline, and layers monitoring plus security detection around the data flow.

Planned deliverables:

- A working cloud-deployed digital twin with dashboard visibility.
- A documented OT/IT threat model.
- At least two attack scenarios, including false data injection.
- Reproducible infrastructure as code.
- CI/CD gates for quality, security, infrastructure, and container checks.
- A final written report with architecture, attack runs, detection results, and
  lessons learned.

## Architecture

<p align="center">
  <img src="docs/assets/gridguard-architecture.svg" alt="GridGuard architecture diagram" width="100%">
</p>

The overview separates the locally verified telemetry path from the
Terraform-defined AWS target. Blue carries telemetry, green carries detection
or review, red marks attack or blocked paths, and dashed gray marks delivery
guardrails. The Modbus ingestor is the sole service permitted to cross the
simulated OT/cloud boundary.

The [full architecture guide](docs/02-architecture.md) includes a detailed
[AWS deployment view](docs/assets/gridguard-aws-deployment.svg), an
[attack-to-alert data-flow view](docs/assets/gridguard-detection-flow.svg), and
the exact status, trust invariants, omissions, and recorded outcomes behind
each figure. [Diagram provenance](docs/assets/README.md) records the official
icon sources and render-validation process.

## Repository Layout

```text
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml
├── infra/
│   ├── images/
│   ├── local/
│   ├── services/
│   └── terraform/environments/
│       ├── aws-sandbox/
│       └── local-dev/
├── scripts/ci/
│   ├── all.sh
│   ├── validate-docs.sh
│   ├── validate-docker.sh
│   ├── validate-python.sh
│   ├── validate-repo-hygiene.sh
│   ├── validate-workflows.sh
│   └── validate-terraform.sh
├── docs/
│   ├── devsecops-track/
│   └── power-track/
├── power-sim/
├── Makefile
└── README.md
```

Important entry points:

| Need | Start Here |
| --- | --- |
| Project overview | [README.md](README.md) |
| Scope and guardrails | [docs/01-project-scope.md](docs/01-project-scope.md) |
| Architecture and stack | [docs/02-architecture.md](docs/02-architecture.md) |
| Diagram provenance and validation | [docs/assets/README.md](docs/assets/README.md) |
| Timeline | [docs/03-timeline.md](docs/03-timeline.md) |
| Integration checkpoints | [docs/04-integration-checkpoints.md](docs/04-integration-checkpoints.md) |
| Attack-run template | [docs/05-attack-log-template.md](docs/05-attack-log-template.md) |
| CI/CD plan | [docs/06-ci-cd.md](docs/06-ci-cd.md) |
| Local fake-data pipeline | [docs/07-local-fake-data-pipeline.md](docs/07-local-fake-data-pipeline.md) |
| Modbus handoff contract | [docs/08-modbus-handoff-contract.md](docs/08-modbus-handoff-contract.md) |
| Detection output contract | [docs/09-detection-output-contract.md](docs/09-detection-output-contract.md) |
| Local red/blue lab | [docs/10-local-red-blue-lab.md](docs/10-local-red-blue-lab.md) |
| AWS cloud handoff | [docs/11-aws-cloud-handoff.md](docs/11-aws-cloud-handoff.md) |
| Security assurance controls | [docs/12-security-assurance.md](docs/12-security-assurance.md) |
| AWS runtime evidence | [docs/13-aws-runtime-evidence.md](docs/13-aws-runtime-evidence.md) |
| AWS Terraform runbook | [infra/terraform/environments/aws-sandbox/README.md](infra/terraform/environments/aws-sandbox/README.md) |
| Power track plan | [docs/power-track/execution-plan.md](docs/power-track/execution-plan.md) |
| DevSecOps track plan | [docs/devsecops-track/execution-plan.md](docs/devsecops-track/execution-plan.md) |

## Tracks

### Power Systems

The Power Systems track owns the physics and telemetry source:

- Build and validate an IEEE 13-bus or 34-bus distribution feeder.
- Run time-series simulation with load variation and distributed generation.
- Expose measurements through Modbus TCP first, with DNP3 as a stretch goal.
- Build baseline bad-data detection.
- Design naive and stealthy false data injection attacks.

Source will live in [power-sim](power-sim).

### DevSecOps And Cloud Infrastructure

The DevSecOps track owns the cloud pipeline and defenses:

- Build cloud infrastructure with Terraform.
- Preserve OT/cloud network segmentation.
- Ingest telemetry into a time-series database.
- Provision dashboards and observability.
- Add IDS, anomaly detection, SIEM alerting, and secrets management.
- Maintain CI/CD quality and security gates.

Source will live in [infra](infra).

## Current Status

The repository contains a working local red/blue lab. A `pandapower` model of
the IEEE 13-node feeder runs a deterministic 24-hour demand and PV profile,
serves live measurements over Modbus TCP, and feeds InfluxDB through the
receiver-side ingestor. Grafana dashboards and alert rules cover the telemetry,
while naive and coordinated in-envelope attack replays exercise the detection
path. The default-off AWS foundation is deployed in a dedicated `us-east-1`
sandbox with its VPC, flow logs, security groups, private ECR repositories, ECS
cluster, and bounded IAM roles verified. Billable runtime resources remain
disabled outside supervised experiments; runtime infrastructure and dormant
services exist with desired counts at zero. A retained immutable-subject OIDC
role produced a clean remote Terraform plan; no GitHub workflow can apply
infrastructure.

Current CI is intentionally future-ready:

- Documentation and repository hygiene checks run immediately.
- Python validation activates once Python files exist.
- Terraform formatting, validation, and native tests run for applicable roots.
- Docker and Compose validation activate once container artifacts exist.
- Gitleaks and Trivy run in GitHub Actions for security coverage.

## Local Development

Clone the repository:

```bash
git clone https://github.com/AnouarMohamed/grid-scada-security.git
cd grid-scada-security
```

Run the full local validation suite:

```bash
make ci
```

Run focused checks:

```bash
make docs
make python
make terraform
make docker
```

The local suite is designed to skip surfaces that do not exist yet, while still
becoming strict as new source files are added.

Start the local fake-data stack:

```bash
cp .env.example .env
make stack-up
make stack-smoke
make stack-dashboard-smoke
```

The dashboard smoke test also verifies the Grafana alert rules and required
InfluxDB telemetry tags.

Grafana is available on `http://127.0.0.1:3000`. InfluxDB is available on
`http://127.0.0.1:8086`. See
[docs/07-local-fake-data-pipeline.md](docs/07-local-fake-data-pipeline.md) for
the full runbook.

Exercise the receiver-side Modbus contract with fixture registers:

```bash
make stack-modbus-up
make stack-modbus-smoke
```

See [docs/08-modbus-handoff-contract.md](docs/08-modbus-handoff-contract.md)
for the register-map contract and simulator handoff rules.

Run the complete local simulator pipeline:

```bash
make stack-live-up
make stack-live-smoke
make stack-dashboard-smoke
```

Replay the two attack scenarios:

```bash
make stack-naive-up
make stack-naive-smoke

make stack-stealthy-up
make stack-stealthy-smoke
```

See [docs/10-local-red-blue-lab.md](docs/10-local-red-blue-lab.md) for the
workflow and expected detector behavior.

## CI/CD

The main CI workflow is [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
It runs on pull requests, pushes to `main`, and manual dispatch.

CI jobs:

- **Repository Hygiene**: line endings, final newline, trailing whitespace,
  ignored tracked files, oversized files, and secret-ignore sanity checks.
- **Documentation**: Markdown fence balance and relative-link validation.
- **CloudFormation**: template parsing and exact plan-only OIDC policy/trust
  invariants.
- **Python Lint, Test, SAST, and Audit**: reproducibly pinned tooling, Ruff,
  Bandit, pip-audit, pytest on Python 3.12 and 3.14, and an 80% aggregate
  coverage floor.
- **Workflow Policy**: actionlint and yamllint plus immutable action revision,
  explicit permissions, and event-trigger checks.
- **Terraform Format, Validate, and Test**: `terraform fmt`, init without a
  backend, validate, and native tests when a root contains `tests/`.
- **Docker and Compose Validation**: Compose config validation, Docker image
  builds, vulnerability reporting, and a blocking critical-vulnerability gate.
- **Secrets and Dependency Scans**: Gitleaks plus Trivy filesystem, secret, and
  misconfiguration scanning.
- **CI Gate**: single required status check for branch protection.

Manual deployment is defined in
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml). It runs only
Terraform `plan` for the repository's AWS sandbox root, uses the protected
`sandbox` GitHub environment, and authenticates through a bounded OIDC role
instead of static access keys. Runtime apply remains a separate local operator
procedure.

The `main` branch is protected with:

- Require pull requests into `main`.
- Require an up-to-date, passing `CI Gate`.
- Enforce the rules for administrators.
- Require review conversations to be resolved.
- Require branches to be up to date before merge.
- Disable force pushes and branch deletion.

The approval count remains zero while this is a solo-maintainer repository. Add
at least one required approval when a second maintainer joins.

## Integration Milestones

GridGuard succeeds only when both tracks meet at defined handoff points.

1. **Telemetry handoff**: Power track provides live Modbus telemetry and a
   register map; DevSecOps confirms ingestion into database and dashboard.
2. **First attack run**: Power track injects an obvious bad value; DevSecOps
   confirms detection and SIEM alerting.
3. **Stealthy attack run**: both tracks measure whether topology-consistent FDIA
   is detected and how long detection takes.
4. **Final review**: validate the full system, report, and demo path.

Details are in
[docs/04-integration-checkpoints.md](docs/04-integration-checkpoints.md).

## Security Principles

- Keep the OT/IT boundary visible in architecture, network policy, and tests.
- Never commit credentials, tokens, private keys, `.env` files, state files, or
  local cloud configuration.
- Prefer OIDC and short-lived cloud credentials for CI/CD.
- Treat Terraform state as sensitive.
- Add detection logic with repeatable attack logs, not one-off manual demos.
- Keep every attack scenario grounded in realistic power-system security
  behavior.

## Roadmap

Near-term:

- Separately design the apply role and environment approval without broadening
  the verified plan-only identity.
- Configure private operator access and the secret procedure; then enable
  runtime with zero tasks before scaling services to one.
- Calibrate the balanced feeder approximation against published IEEE reference
  results or promote it to an unbalanced model.
- Add a residual/state-estimation detector beyond envelope checks.

Mid-term:

- Add Suricata or Zeek rules for suspicious OT traffic.
- Add Wazuh or another SIEM target for detection events.
- Turn the coordinated in-envelope replay into a state-estimator-derived FDIA.

Later:

- Add mTLS between services.
- Add SIEM alert wiring.
- Add Terraform plan artifacts to pull requests.
- Add SBOM generation and signed image publishing.
- Add automated end-to-end red/blue smoke tests.

## Contributing

Before opening or merging a change:

1. Read the relevant track execution plan.
2. Keep changes scoped to the correct track directory.
3. Run `make ci`.
4. Update docs when interfaces change, especially Modbus registers,
   infrastructure assumptions, or attack-run behavior.
5. Use pull requests into `main` once branch protection is enabled.

For shared vocabulary, see [docs/00-glossary.md](docs/00-glossary.md).
