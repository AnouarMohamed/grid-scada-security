# Local Fake-Data Pipeline

This is the DevSecOps track's first real integration surface. It lets the team
stand up telemetry storage and dashboards before the Power Systems track ships
the Modbus simulator.

The stack is intentionally shaped like the future system:

```text
[fake-grid-source] -- OT network --> [telemetry-ingestor] -- cloud network --> [InfluxDB]
                                                                            |
                                                                            v
                                                                        [Grafana]
```

## What Runs

| Service | Zone | Host Exposure | Purpose |
| --- | --- | --- | --- |
| `fake-grid-source` | `ot-sim` | None | Generates synthetic feeder telemetry. |
| `telemetry-ingestor` | `ot-sim` + `cloud-core` | None | Polls the source and writes line protocol to InfluxDB. |
| `influxdb` | `cloud-core` | `127.0.0.1:8086` | Stores time-series telemetry. |
| `grafana` | `cloud-core` | `127.0.0.1:3000` | Displays the provisioned GridGuard dashboard. |

The fake source is not published to the host. Only the ingestor is dual-homed.
That is deliberate: the ingestor is the temporary stand-in for the future
Modbus/DNP3 ingestion service.

The receiver-side Modbus contract can be exercised separately:

```bash
make stack-modbus-up
make stack-modbus-smoke
```

That profile uses fixture register values and the same `grid_telemetry`
measurement. See [docs/08-modbus-handoff-contract.md](08-modbus-handoff-contract.md).

## Why InfluxDB First

The project scope allows InfluxDB or TimescaleDB. This first integration pass
uses InfluxDB because:

- It has a direct line-protocol write path.
- Grafana provisioning is straightforward.
- It fits SCADA-style measurements with tags for feeder, bus, phase, signal,
  scenario, and source.
- It keeps the fake-data generator dependency-free.

TimescaleDB can still be introduced later if the team wants SQL-first analysis.
The important contract is not the database brand; it is the telemetry schema,
network boundary, and dashboard provisioning discipline.

## Start

Copy the example environment if you want to override ports or local passwords:

```bash
cp .env.example .env
```

The default InfluxDB bucket retention is `168h`, keeping the local telemetry
volume bounded during repeated lab runs. Retention is applied when the InfluxDB
volume is initialized; if you change `INFLUXDB_RETENTION` after first startup,
run `make stack-reset` before starting the stack again.

Start the stack:

```bash
make stack-up
```

Run the smoke test:

```bash
make stack-smoke
```

Validate the provisioned dashboard against live InfluxDB data:

```bash
make stack-dashboard-smoke
```

The dashboard smoke also verifies provisioned Grafana alert rules for attack
flags, out-of-envelope voltage, and stale telemetry.

Open Grafana at:

```text
http://127.0.0.1:3000
```

Default local credentials come from `.env.example`. Change them in `.env` on
any shared workstation.

## Stop Or Reset

Stop containers but keep data:

```bash
make stack-down
```

Remove containers and local volumes:

```bash
make stack-reset
```

Follow logs:

```bash
make stack-logs
```

## Telemetry Schema

InfluxDB measurement:

```text
grid_telemetry
```

Tags:

- `feeder`
- `bus`
- `phase`
- `scenario`
- `signal`
- `source`

Fields:

- `value`
- `quality`
- `attack_flag`

Current signals:

- `voltage_pu`
- `current_a`
- `real_power_kw`
- `reactive_power_kvar`
- `frequency_hz`

This schema is deliberately close to what the Modbus ingestion service should
emit later. When the real register map arrives, the ingestor should preserve
these tags and fields unless there is a documented reason to change them.

## Boundary Rules

- `fake-grid-source` is OT-side only.
- `influxdb` and `grafana` are cloud-side only.
- `telemetry-ingestor` is the only service connected to both networks.
- Host ports bind to `127.0.0.1`, not all interfaces.
- Grafana suggested plugin preinstall and plugin auto-update are disabled for
  deterministic local startup.
- Grafana provisioning mounts the datasource, dashboard, and alerting
  directories; default empty provisioning directories from the container image
  remain intact.
- Local credentials are examples only; cloud credentials must use OIDC or a
  secrets manager.

## Replacement Path For Real Modbus

When the Power Systems track delivers Modbus:

1. Keep `influxdb` and `grafana`.
2. Replace `fake-grid-source` with the Modbus emulator.
3. Replace `telemetry-ingestor` mode with a real Modbus polling/listening
   service.
4. Preserve the `grid_telemetry` schema or document a migration.
5. Add an integration test that proves one register-map value reaches InfluxDB
   and Grafana.

## Troubleshooting

Show status:

```bash
make stack-ps
```

Common issues:

- Port `3000` or `8086` is already in use. Override `GRAFANA_PORT` or
  `INFLUXDB_PORT` in `.env`.
- InfluxDB retention, bucket, or admin credentials changed after the volume was
  initialized. Run `make stack-reset` to recreate local volumes.
- Grafana dashboard is empty. Wait one minute, then run `make stack-smoke` to
  confirm telemetry exists in InfluxDB.
