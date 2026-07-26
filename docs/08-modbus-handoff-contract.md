# Modbus Handoff Contract

This document defines the DevSecOps receiver-side contract for the future Power
Systems Modbus simulator.

The goal is to make the telemetry platform ready before the real simulator is
delivered. The current `modbus-fixture` profile uses deterministic register
values, but it exercises the same register-map parser, scaling logic, InfluxDB
schema, and Grafana path expected from the real simulator.

## Ownership

DevSecOps owns:

- Register-map contract format.
- Modbus ingestor service.
- Network placement and OT/IT boundary rules.
- InfluxDB write path.
- Grafana and downstream observability.
- CI and smoke tests proving contract compatibility.

Power Systems owns:

- Physical signal semantics.
- Final register addresses and scaling.
- Simulator timing and protocol behavior.
- Attack values and physical plausibility.

Both tracks review changes to `infra/contracts/register-maps/`.

## Contract Format

Register maps live under:

```text
infra/contracts/register-maps/
```

The machine-readable address is `address`, which is always the zero-based
Modbus PDU address. The `reference` field can carry human notation such as
`40001`, but ingestion does not use it for polling.

Each register entry must define:

- `name`
- `address`
- `reference`
- `function`
- `data_type`
- `scale`
- `offset`
- `unit`
- `bus`
- `phase`
- `signal`
- `quality`
- `attack_flag`

Supported functions today:

- `holding_register`

Supported data types today:

- `uint16`
- `int16`

## Telemetry Output

The ingestor writes the same InfluxDB measurement as the fake-data stack:

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

This keeps Grafana and future detectors stable across fake, fixture, and real
Modbus sources.

## Local Fixture Profile

Start the receiver-side Modbus fixture path:

```bash
make stack-modbus-up
make stack-modbus-smoke
```

This starts InfluxDB, Grafana, and `modbus-ingestor-fixture`. It does not need
the real simulator.

The fixture values live at:

```text
infra/contracts/register-maps/fixtures/ieee13-baseline-registers.json
```

Validate the register-map and fixture contract without starting containers:

```bash
make modbus-contracts
```

That check must pass before any register-map change is handed across tracks.

## DevSecOps Pre-Handoff Checklist

Complete this before the Power Systems track delivers the real simulator:

- `make modbus-contracts` passes.
- `make stack-modbus-up` starts InfluxDB, Grafana, and the fixture ingestor.
- `make stack-modbus-smoke` observes `source=modbus_fixture` telemetry rows.
- Grafana shows the provisioned GridGuard dashboard from the shared
  `grid_telemetry` measurement.
- Any register-map edits are reviewed by both tracks before merge.

Do not ask the Power Systems track to debug cloud storage, Grafana
provisioning, or receiver-side scaling issues until this checklist is green.

## Real Simulator Swap

When the Power Systems simulator is ready:

1. Keep `influxdb`, `grafana`, and the Modbus ingestor image.
2. Change `GRIDGUARD_MODBUS_MODE` from `fixture` to `tcp`.
3. Point `GRIDGUARD_MODBUS_HOST` and `GRIDGUARD_MODBUS_PORT` at the simulator.
4. Replace or extend `ieee13-demo.json` with the final register map.
5. Run a smoke test filtered to `source=modbus_tcp`.

The ingestor is intentionally the only component that should cross from the OT
segment into the cloud telemetry zone.

The simulator handoff is acceptable when the Power Systems track can provide:

- A running Modbus TCP endpoint reachable from the ingestor on the OT segment.
- The Modbus unit id.
- A reviewed register map using zero-based PDU addresses.
- Scaling rules that keep raw register values inside the declared data type.
- At least one stable baseline run for DevSecOps smoke testing.
- One intentionally bad-value run before FDIA work starts. It should use the
  same register map, set `scenario=naive-bad-value`, and either set
  `attack_flag=1` on affected values or clearly document the affected
  bus/signal/time window so DevSecOps can validate alerting.

Detector output from DevSecOps-owned rules must follow
[docs/09-detection-output-contract.md](09-detection-output-contract.md).
