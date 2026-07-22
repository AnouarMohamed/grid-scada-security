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

## Real Simulator Swap

When the Power Systems simulator is ready:

1. Keep `influxdb`, `grafana`, and the Modbus ingestor image.
2. Change `GRIDGUARD_MODBUS_MODE` from `fixture` to `tcp`.
3. Point `GRIDGUARD_MODBUS_HOST` and `GRIDGUARD_MODBUS_PORT` at the simulator.
4. Replace or extend `ieee13-demo.json` with the final register map.
5. Run a smoke test filtered to `source=modbus_tcp`.

The ingestor is intentionally the only component that should cross from the OT
segment into the cloud telemetry zone.
