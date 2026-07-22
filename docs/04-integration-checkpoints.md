# Integration Checkpoints

Points where the two tracks must actively sync, not just work in parallel.

## Checkpoint 1 — Telemetry handoff (end of week 4)

**Power track delivers:**
- A running Modbus TCP server exposing live simulation output
- A documented register map (which register = which measurement, and the
  scale factor used to fit floating-point values into 16-bit registers)

**DevSecOps track confirms:**
- Ingestion service can read the feed and values appear correctly in the
  time-series DB and Grafana dashboard

**Do not proceed to attack work (Power track Step 6+) until this works.**

## Checkpoint 2 — First attack run (week 5–6)

**Power track delivers:** a naive (easily detectable) false data injection
against the live feed, or an intentionally bad-value run using the same Modbus
contract before the full FDIA implementation is ready.

**DevSecOps track confirms:** the IDS/anomaly detection layer catches it, and
an alert appears in Grafana or the SIEM using the detection output contract in
`docs/09-detection-output-contract.md`.

This proves the full pipeline works end-to-end before testing anything
subtle.

## Checkpoint 3 — Stealthy attack run (week 7–8)

**Power track delivers:** a stealthy, topology-consistent FDIA.

**Both tracks jointly:** measure whether it's detected, how long detection
takes (if at all), and what the downstream impact would be if undetected.
Log every run using `docs/05-attack-log-template.md`.

## Checkpoint 4 — Final review (week 9–10)

Walk through the full system together, sanity-check the write-up, and make
sure both tracks' contributions are clearly represented.
