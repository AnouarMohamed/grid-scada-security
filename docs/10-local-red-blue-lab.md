# Local Red/Blue Lab

The live profile exercises the complete local path:

```text
pandapower feeder -> Modbus TCP -> telemetry ingestor -> InfluxDB -> Grafana
                                            |
                                            +-> grid_detection
```

The simulator advances one hour of its deterministic demand/PV profile every
two seconds. Only the simulator and ingestor join the internal `ot-sim`
network; only the ingestor also joins `cloud-core`.

## Baseline

```bash
make stack-live-up
make stack-live-smoke
make stack-dashboard-smoke
```

Expected result: telemetry changes over time, all dashboard queries succeed,
and the ingestor emits no sample-level detections.

## Naive Bad Value

```bash
make stack-naive-up
make stack-naive-smoke
```

The replay forces phase-A voltage to `0.88 pu` and exaggerates phase-A current.
Expected detectors:

- `voltage-envelope`
- `attack-flag-forwarder`

## Coordinated In-Envelope Replay

```bash
make stack-stealthy-up
make stack-stealthy-smoke
```

The replay applies coordinated shifts to voltage, current, real power, and
reactive power while keeping voltage within the static envelope. The envelope
detector should remain quiet; `attack-flag-forwarder` preserves ground truth
for evaluation.

This scenario demonstrates the limitation of threshold-only detection. It is
not yet a state-estimator-derived, topology-consistent FDIA.

## Inspect And Stop

```bash
make stack-ps
make stack-logs
make stack-down
```

Grafana is available at `http://127.0.0.1:3000` and InfluxDB at
`http://127.0.0.1:8086` using the credentials in `.env`.

## Recorded Local Verification

On 2026-09-10, the baseline profile produced live `modbus_tcp` telemetry and
all provisioned dashboard queries passed. The naive replay produced both
detector families. The coordinated in-envelope replay produced only the
ground-truth forwarder, confirming that the voltage-envelope detector did not
identify it.
