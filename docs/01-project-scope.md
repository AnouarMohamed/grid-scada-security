# Project Scope

## Concept

A cloud-hosted digital twin of an electrical distribution feeder that runs
continuously, streams realistic SCADA-style telemetry, and is both attacked
and defended as if it were real critical infrastructure.

- The **Power Systems track** builds the grid model, runs time-series
  simulation, and generates realistic telemetry, then designs attacks
  (False Data Injection) against that telemetry.
- The **DevSecOps track** builds the pipeline, infrastructure, monitoring,
  and security defenses that ingest and protect that telemetry.

This mirrors a real, active problem space: utilities moving grid monitoring
into the cloud, and grid cybersecurity (FDIA, SCADA protocol attacks) being an
active research and industry area. It's also thematically close to the U.S.
Department of Energy's CyberForce Competition (run by Argonne National
Laboratory) — worth checking as a benchmark or stretch target; verify current
details on their site since specifics change year to year.

## Deliverables

1. A working, cloud-deployed digital twin (accessible via dashboard)
2. A documented threat model for the pipeline
3. At least 2 attack scenarios demonstrated and (attempted to be) detected
4. Infra-as-code, reproducible from scratch
5. A written report — the portfolio piece for both of you
6. Optional: a short demo video

## Scope guardrails

- Use a real solver and a standard test feeder (IEEE 13-bus or 34-bus) — not
  invented grid physics.
- Preserve a real OT/IT boundary between simulation and cloud — that boundary
  is the entire point; don't flatten the network into one flat zone.
- Ground attack scenarios in real power-systems security literature (FDIA is
  a well-studied area), not invented mechanics.
- **Week 4 scope check-in**: if DNP3, Kubernetes, and ML-based detection all
  still feel unstarted by week 4, cut down to Modbus + Docker Compose +
  statistical detection. A finished simple system beats an unfinished
  ambitious one.

See `docs/02-architecture.md` for the technical architecture and stack, and
`docs/03-timeline.md` for the phased schedule.
