# GridGuard Modbus Ingestor

This service is the DevSecOps-owned receiver-side skeleton for the future
Power Systems Modbus/DNP3 handoff.

It currently supports two modes:

- `fixture`: read deterministic register values from a JSON fixture. This is
  used for local integration and CI before the real simulator exists.
- `tcp`: read Modbus TCP holding registers from a simulator using zero-based
  PDU addresses from the register-map contract.

Both modes emit the shared `grid_telemetry` measurement to InfluxDB.

`GRIDGUARD_MODBUS_UNIT_ID` is optional. When it is unset, the ingestor uses the
unit id declared in the register-map contract; when it is set, the runtime value
is treated as an explicit simulator override.

Key commands:

```bash
python -m gridguard_modbus_ingestor validate-map
python -m gridguard_modbus_ingestor ingest-once
python -m gridguard_modbus_ingestor ingest
python -m gridguard_modbus_ingestor healthcheck
```

The register-map contract lives in `infra/contracts/register-maps/`.
