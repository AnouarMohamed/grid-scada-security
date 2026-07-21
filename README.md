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

```text
[Grid Simulation Engine] -> [Protocol Emulator] -> [Cloud Ingestion] -> [Time-Series DB]
   pandapower/OpenDSS       Modbus TCP/DNP3        service/queue          InfluxDB/TimescaleDB
                                                         |
                                                         v
                                                  [Grafana Dashboard]
                                                         |
                                                         v
                                             [IDS / Anomaly Detection]
                                             Suricata/Zeek + stats/ML
                                                         |
                                                         v
                                                   [SIEM / Alerting]
                                                     Wazuh or ELK

[Attack Simulator] -> false data injection, flooding, or MITM-style tests
```

The protocol emulator to cloud ingestion link is the main simulated OT/IT
boundary. That boundary must stay explicit through network segmentation,
controlled connectivity, and eventually mTLS.

Full architecture notes live in [gridguard/docs/02-architecture.md](gridguard/docs/02-architecture.md).

## Repository Layout

```text
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml
├── scripts/ci/
│   ├── all.sh
│   ├── validate-docs.sh
│   ├── validate-docker.sh
│   ├── validate-python.sh
│   ├── validate-repo-hygiene.sh
│   └── validate-terraform.sh
├── gridguard/
│   ├── README.md
│   ├── docs/
│   ├── power-sim/
│   └── infra/
├── Makefile
└── README.md
```

Important entry points:

| Need | Start Here |
| --- | --- |
| Project overview | [gridguard/README.md](gridguard/README.md) |
| Scope and guardrails | [gridguard/docs/01-project-scope.md](gridguard/docs/01-project-scope.md) |
| Architecture and stack | [gridguard/docs/02-architecture.md](gridguard/docs/02-architecture.md) |
| Timeline | [gridguard/docs/03-timeline.md](gridguard/docs/03-timeline.md) |
| Integration checkpoints | [gridguard/docs/04-integration-checkpoints.md](gridguard/docs/04-integration-checkpoints.md) |
| Attack-run template | [gridguard/docs/05-attack-log-template.md](gridguard/docs/05-attack-log-template.md) |
| CI/CD plan | [gridguard/docs/06-ci-cd.md](gridguard/docs/06-ci-cd.md) |
| Power track plan | [gridguard/docs/power-track/execution-plan.md](gridguard/docs/power-track/execution-plan.md) |
| DevSecOps track plan | [gridguard/docs/devsecops-track/execution-plan.md](gridguard/docs/devsecops-track/execution-plan.md) |

## Tracks

### Power Systems

The Power Systems track owns the physics and telemetry source:

- Build and validate an IEEE 13-bus or 34-bus distribution feeder.
- Run time-series simulation with load variation and distributed generation.
- Expose measurements through Modbus TCP first, with DNP3 as a stretch goal.
- Build baseline bad-data detection.
- Design naive and stealthy false data injection attacks.

Source will live in [gridguard/power-sim](gridguard/power-sim).

### DevSecOps And Cloud Infrastructure

The DevSecOps track owns the cloud pipeline and defenses:

- Build cloud infrastructure with Terraform.
- Preserve OT/cloud network segmentation.
- Ingest telemetry into a time-series database.
- Provision dashboards and observability.
- Add IDS, anomaly detection, SIEM alerting, and secrets management.
- Maintain CI/CD quality and security gates.

Source will live in [gridguard/infra](gridguard/infra).

## Current Status

The repository currently contains the project documentation, source tree
skeleton, and CI/CD foundation. Application code, Terraform modules, container
definitions, and cloud deployment targets are expected to land as the two tracks
move through the execution plans.

Current CI is intentionally future-ready:

- Documentation and repository hygiene checks run immediately.
- Python validation activates once Python files exist.
- Terraform validation activates once Terraform files exist.
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

## CI/CD

The main CI workflow is [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
It runs on pull requests, pushes to `main`, and manual dispatch.

CI jobs:

- **Repository Hygiene**: line endings, final newline, trailing whitespace, and
  secret-ignore sanity checks.
- **Documentation**: Markdown fence balance and relative-link validation.
- **Python Lint, Test, and SAST**: Ruff, Bandit, dependency installation, and
  pytest when tests exist.
- **Terraform Format and Validate**: `terraform fmt`, init without backend, and
  validate.
- **Docker and Compose Validation**: Compose config validation and Docker image
  builds.
- **Secrets and Dependency Scans**: Gitleaks plus Trivy filesystem, secret, and
  misconfiguration scanning.
- **CI Gate**: single required status check for branch protection.

Manual deployment is scaffolded in
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml). It supports
Terraform `plan` and `apply`, expects GitHub environments, and is prepared for
cloud authentication through OIDC instead of static access keys.

Recommended branch protection:

- Require pull requests into `main`.
- Require `CI Gate`.
- Require branches to be up to date before merge.
- Disable force pushes to `main`.
- Add required review once multiple contributors are pushing implementation
  code.

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
[gridguard/docs/04-integration-checkpoints.md](gridguard/docs/04-integration-checkpoints.md).

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

- Add Python project structure for `power-sim`.
- Add a minimal Modbus telemetry server and client test.
- Add Terraform provider/backend skeleton under `gridguard/infra`.
- Add Docker Compose for local fake telemetry, database, and dashboard smoke
  testing.

Mid-term:

- Add live time-series simulation and register-map documentation.
- Add ingestion service tests.
- Add Grafana provisioning.
- Add Suricata or Zeek rules for suspicious OT traffic.
- Add anomaly detection against telemetry values.

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

For shared vocabulary, see [gridguard/docs/00-glossary.md](gridguard/docs/00-glossary.md).
