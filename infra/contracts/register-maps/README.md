# Register Map Contracts

This directory is the DevSecOps-owned handoff point between the Power Systems
track and the telemetry platform.

The contract uses zero-based Modbus PDU addresses. The human-facing
`reference` field can carry values such as `40001`, but ingestion code uses the
integer `address` field so there is no ambiguity around one-based register
notation.

Required telemetry tags stay aligned with the shared `grid_telemetry` schema:

- `feeder`
- `bus`
- `phase`
- `scenario`
- `signal`
- `source`

Required fields:

- `value`
- `quality`
- `attack_flag`

The fixture file under `fixtures/` is not the physical truth model. It is a
deterministic CI fixture that lets the DevSecOps stack prove register-map
parsing, scaling, and InfluxDB writes before the real simulator exists.
