# Detection Output Contract

This document defines the first stable output shape for GridGuard detectors and
alert bridges. It is separate from raw grid telemetry so detection logic can
evolve without breaking dashboards that read `grid_telemetry`.

## Measurement

Detector output writes to:

```text
grid_detection
```

## Required Tags

Use tags only for bounded-cardinality routing and filtering:

- `detector` - detector or rule family, for example `voltage-envelope`.
- `severity` - `info`, `warning`, or `critical`.
- `source` - telemetry source under analysis, for example `modbus_tcp`.
- `scenario` - scenario label, for example `baseline` or `naive-bad-value`.
- `feeder` - feeder identifier.
- `signal` - source signal under analysis.

Optional tags:

- `bus`
- `phase`
- `rule_uid`

Do not put timestamps, UUIDs, raw payloads, credentials, or free-form messages
in tags. Those belong in fields or external logs.

## Required Fields

- `score` - numeric detector score. Use `0.0` when the detector is boolean.
- `threshold` - numeric threshold used for this decision.
- `alert_flag` - integer `0` or `1`; Grafana/SIEM rules should alert on `1`.
- `message` - short human-readable explanation.

Optional fields:

- `confidence` - `0.0` to `1.0` confidence value.
- `observed_time_ns` - original telemetry sample time when detection is delayed.
- `event_id` - string identifier used by logs or reports.

## Timestamp

Use the detection decision time as the InfluxDB point timestamp. If the
detector is evaluating an older telemetry sample, include `observed_time_ns` as
a field.

## Example

```text
grid_detection,bus=bus-632,detector=voltage-envelope,feeder=ieee-13-demo,phase=a,rule_uid=gridguard-voltage-out-of-range,scenario=naive-bad-value,severity=warning,signal=voltage_pu,source=modbus_tcp alert_flag=1i,message="voltage outside 0.95-1.05 pu envelope",score=1.071,threshold=1.05 1790000000000000000
```

## First Detector Targets

The initial DevSecOps detector work should produce events for:

- `voltage-envelope` - voltage below `0.95` pu or above `1.05` pu.
- `telemetry-stale` - no telemetry rows observed in the expected window.
- `attack-flag-forwarder` - forwards upstream `attack_flag=1` telemetry into
  the detection stream.

The Power Systems track owns physically plausible bad values and FDIA design.
The DevSecOps track owns this detection output schema, alert routing, and
downstream evidence capture.
