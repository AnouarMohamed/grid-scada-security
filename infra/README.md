# infra/

DevSecOps track source lives here: Terraform contracts, local integration
stack assets, ingestion services, dashboard provisioning, IDS rules, and SIEM
configuration.

## Current Contents

```text
infra/
├── local/
│   └── grafana/
├── services/
│   └── fake-telemetry/
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

## Terraform

Terraform currently defines provider-light contracts for:

- Network zones.
- Boundary services.
- Observability endpoints.
- Security invariants.

Validate with:

```bash
make terraform
```

See `terraform/README.md` for the cloud expansion path.

## Build Order

See `../docs/devsecops-track/execution-plan.md` for the full DevSecOps track
plan.
