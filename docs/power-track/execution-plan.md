# Execution Plan — Power Systems Track

1. **Environment setup** — Python venv, `pandapower`, `pymodbus`, shared repo.
   *Done when:* the built-in pandapower example network runs without errors.

2. **Baseline grid model** — build the IEEE 13-bus feeder from published
   data, run `pp.runpp()`, validate against reference results.
   *Done when:* voltages match published results within a small tolerance.

3. **Time-varying load profile** — 24-hour load curve via
   `pandapower.timeseries`, save results per timestep.
   *Done when:* you have a time series showing realistic daily variation.

4. **Add DER (PV)** — add an `sgen` element with a solar generation curve,
   observe voltage-rise effects during high-PV/low-load hours.
   *Done when:* you can plot the difference PV makes to the voltage profile.

5. **Expose telemetry over Modbus** — `pymodbus` TCP server, documented
   register map, scaled floating-point values, updates on an interval.
   *Done when:* a standalone client can read live, changing values.

   **→ Integration checkpoint 1 with DevSecOps track — see
   `docs/04-integration-checkpoints.md`. Do not proceed until this works.**

6. **Bad-data baseline detector** — residual/threshold check, or a simple
   weighted least squares state estimator.
   *Done when:* it flags an obviously wrong injected value but stays quiet
   otherwise.

7. **Design FDIA attacks** — a naive attack (caught by your own detector) and
   a stealthy, topology-consistent attack (not caught).
   *Done when:* you can demonstrate both against your own baseline.

8. **Joint red/blue exercise** — run both attacks against the full pipeline
   once the DevSecOps track's IDS/SIEM is live. Log every run using
   `docs/05-attack-log-template.md`.

9. **Write-up** — architecture, grid model validation, attack design and
   reasoning, results table, lessons learned.
