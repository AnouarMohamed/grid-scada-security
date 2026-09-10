# infra/

DevSecOps track source lives here: Terraform contracts, local integration
stack assets, ingestion services, dashboard provisioning, IDS rules, and SIEM
configuration.

## Current Contents

```text
infra/
├── contracts/
│   └── register-maps/
├── images/
│   ├── grafana/
│   └── influxdb/
├── local/
│   └── grafana/
├── services/
│   ├── fake-telemetry/
│   └── modbus-ingestor/
└── terraform/
```

## Local Fake-Data Pipeline

The first working pipeline is Docker Compose based:

```bash
cp .env.example .env
make stack-up
make stack-smoke
```

It starts:

- Synthetic OT telemetry source.
- Dual-homed telemetry ingestor.
- InfluxDB time-series storage.
- Provisioned Grafana dashboard.

The source is not exposed to the host. Only the ingestor crosses from `ot-sim`
to `cloud-core`, preserving the same boundary shape the real Modbus ingestion
service must respect.

Full runbook: `../docs/07-local-fake-data-pipeline.md`.

## Modbus Handoff Contract

The receiver-side Modbus integration is scaffolded under:

```text
infra/contracts/register-maps/
infra/services/modbus-ingestor/
```

Run the fixture-backed contract path with:

```bash
make stack-modbus-up
make stack-modbus-smoke
```

Full handoff notes: `../docs/08-modbus-handoff-contract.md`.

## Live Local Red/Blue Lab

The `live` Compose profile runs the `pandapower` simulator, a Modbus TCP
server, the TCP-mode ingestor, InfluxDB, and Grafana across the modeled OT/cloud
boundary. Baseline, naive bad-value, and coordinated in-envelope scenarios are
available through Make targets. See `../docs/10-local-red-blue-lab.md`.

## Terraform

Terraform includes provider-light local contracts and a concrete AWS sandbox
environment for:

- Two-AZ segmented network zones and explicit boundary rules.
- Private ECS/Fargate services and ECR repositories.
- Encrypted persistent storage, secrets containers, and observability logs.
- Disabled-by-default cost gates and constrained GitHub OIDC trust.

Validate with:

```bash
make terraform
```

See `terraform/README.md` and
`terraform/environments/aws-sandbox/README.md` for the validated cloud shape
and operator handoff.

## Build Order

See `../docs/devsecops-track/execution-plan.md` for the full DevSecOps track
plan.
