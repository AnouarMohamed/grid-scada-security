# Fake Telemetry Service

This service gives the DevSecOps track a realistic telemetry source before the
Power Systems track delivers the real Modbus emulator.

The same image runs in two modes:

- `source`: OT-side HTTP service that generates synthetic grid measurements.
- `ingest`: dual-homed worker that polls the source and writes InfluxDB line
  protocol into the cloud-side time-series database.

The source is intentionally not exposed to the host. In Compose, only the
ingestor can reach both `ot-sim` and `cloud-core`, matching the future boundary
where the real ingestion service will read Modbus/DNP3 and write telemetry.

## Data Shape

Every sample is emitted as the `grid_telemetry` measurement with these tags:

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

The current generator emits voltage, current, real power, reactive power, and
frequency for each bus/phase pair in the IEEE 13-bus demo feeder.

## Local Test

From the repository root:

```bash
python -m pytest infra/services/fake-telemetry/tests
```
