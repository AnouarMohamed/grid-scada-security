# Study Guide — Power Systems Track

## Your role

Own the physics and the data: the grid model, its time-series simulation, the
telemetry it emits, and the attacks designed against that telemetry.

## Study order

### Phase 1 (weeks 1–2): Grid modeling fundamentals
- Power flow refresher: Newton-Raphson/Gauss-Seidel, per-unit system, bus
  types. (Grainger & Stevenson, or Glover/Sarma/Overbye, are the standard
  references if you need a refresher.)
- `pandapower` basics: building a network, `pp.runpp()`, the time-series
  module. Work through their official tutorials directly.
- IEEE 13-bus (or 34-bus) feeder topology and data.

### Phase 2 (weeks 3–4): Telemetry & protocol basics
- Modbus TCP: client/server model, function codes (03/04 read, 06/16 write),
  encoding analog values into registers.
- `pymodbus` client/server examples.
- Stretch: DNP3 basics (outstation/master model, points, classes).

### Phase 3 (weeks 5–7): Security-specific concepts — the core content
- State estimation: weighted least squares from redundant measurements
  (Abur & Expósito's *Power System State Estimation* is the standard
  reference for a deeper read).
- Bad-data detection: residual-based (chi-squared) detection.
- False Data Injection Attacks: the foundational paper is Liu, Ning, and
  Reiter's work on FDIA against state estimation — search for it directly.
  Key idea: naive false data gets caught by bad-data detection; a
  topology-consistent stealthy attack does not.

### Phase 4 (weeks 8–10)
No new heavy content — running joint scenarios and writing up results.

## Self-check

- [ ] Can run power flow on the IEEE 13-bus feeder and explain the results
- [ ] Have a 24h time-series simulation with at least one DER source
- [ ] Can serve simulation output over Modbus TCP, read by a separate client
- [ ] Can explain why a random false reading is caught but a crafted one isn't
- [ ] Have a working baseline bad-data detector
- [ ] Have at least one FDIA scenario that evades your own baseline detector
