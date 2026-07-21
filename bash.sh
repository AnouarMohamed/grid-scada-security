#!/usr/bin/env bash
#
# scaffold-gridguard-docs.sh
#
# Scaffolds a full documentation tree (and matching skeleton source folders)
# for the GridGuard project: a secure cloud-native digital twin of a power
# distribution grid, built jointly by a Power Systems track and a DevSecOps
# track.
#
# Usage:
#   chmod +x scaffold-gridguard-docs.sh
#   ./scaffold-gridguard-docs.sh [target-directory]
#
# Default target directory: ./gridguard
#
set -euo pipefail

ROOT="${1:-gridguard}"

echo "Scaffolding GridGuard project into ./${ROOT} ..."

mkdir -p "${ROOT}"/docs/power-track
mkdir -p "${ROOT}"/docs/devsecops-track
mkdir -p "${ROOT}"/power-sim
mkdir -p "${ROOT}"/infra
mkdir -p "${ROOT}"/.github/workflows

# ---------------------------------------------------------------------------
# README.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/README.md" <<'EOF'
# GridGuard

Secure cloud-native digital twin of a power distribution grid, with a built-in
red-team/blue-team cybersecurity exercise. Built jointly by a Power Systems
track and a DevSecOps/Cloud Infrastructure track.

## What this is

A simulated distribution feeder streams realistic SCADA-style telemetry
(Modbus/DNP3) into a cloud pipeline. The Power track owns the physics and the
attacks; the DevSecOps track owns the infrastructure and the defenses.

## Where to start

| If you are... | Start here |
|---|---|
| New to the project | `docs/01-project-scope.md` |
| On the Power Systems track | `docs/power-track/study-guide.md`, then `docs/power-track/execution-plan.md` |
| On the DevSecOps track | `docs/devsecops-track/study-guide.md`, then `docs/devsecops-track/execution-plan.md` |
| Looking for architecture/tech stack | `docs/02-architecture.md` |
| Confused by the other track's jargon | `docs/00-glossary.md` |
| Tracking milestones | `docs/03-timeline.md` |
| Coordinating a handoff between tracks | `docs/04-integration-checkpoints.md` |
| Logging an attack/defense test | `docs/05-attack-log-template.md` |

## Repo layout

```
gridguard/
├── README.md                        <- you are here
├── docs/
│   ├── 00-glossary.md               <- shared vocabulary between tracks
│   ├── 01-project-scope.md          <- full project scope & rationale
│   ├── 02-architecture.md           <- system architecture & tech stack
│   ├── 03-timeline.md               <- phased milestones
│   ├── 04-integration-checkpoints.md<- where the two tracks must sync
│   ├── 05-attack-log-template.md    <- template for logging attack/defense runs
│   ├── power-track/
│   │   ├── study-guide.md
│   │   └── execution-plan.md
│   └── devsecops-track/
│       ├── study-guide.md
│       └── execution-plan.md
├── power-sim/                       <- Power track source code lives here
│   └── README.md
├── infra/                           <- DevSecOps track source/IaC lives here
│   └── README.md
└── .github/workflows/               <- CI/CD pipelines (DevSecOps track)
```

## Team roles, one line each

- **Power Systems track**: builds the grid model, simulates it over time,
  exposes it as SCADA-style telemetry, and designs the attacks (False Data
  Injection) that test the system.
- **DevSecOps track**: builds the cloud pipeline that ingests that telemetry,
  and the monitoring/IDS/SIEM layer that has to detect the attacks.

The interface between the two is a Modbus/DNP3 telemetry feed — documented in
`docs/04-integration-checkpoints.md`. Neither track is meaningfully testable
without the other, by design.
EOF

# ---------------------------------------------------------------------------
# docs/00-glossary.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/00-glossary.md" <<'EOF'
# Shared Glossary

Enough vocabulary from each track for the other person to follow along,
without needing to become an expert in it.

## Power systems terms (for the DevSecOps person)

- **Power flow**: the calculation of voltage, current, and power at every
  point in a grid, given loads and generation. The core simulation output.
- **Bus**: a node in the grid (roughly: a connection point — a substation, a
  transformer, a load point).
- **DER (Distributed Energy Resource)**: small-scale generation like rooftop
  solar, connected at the distribution level rather than centrally.
- **State estimation**: the process a grid operator uses to reconcile noisy,
  redundant sensor readings into a trusted picture of grid state.
- **Bad-data detection**: the traditional defense that flags sensor readings
  inconsistent with the rest of the system.
- **False Data Injection Attack (FDIA)**: a falsified set of sensor readings
  crafted to be internally consistent enough to evade bad-data detection.

## DevSecOps/cloud terms (for the Power Systems person)

- **IaC (Infrastructure as Code)**: infrastructure defined in text files
  (e.g., Terraform) instead of manually clicked together, so it's
  reproducible.
- **Container**: a packaged, isolated way to run software (Docker); the
  telemetry server and pipeline services will likely run in these.
- **VPC / network segmentation**: splitting a cloud network into isolated
  zones — used here to mimic the real-world separation between operational
  technology (OT) and IT networks.
- **IDS (Intrusion Detection System)**: software watching network traffic for
  attack patterns (e.g., Suricata, Zeek).
- **SIEM**: a system that aggregates security events/alerts into one place
  (e.g., Wazuh, ELK) — where alerts about your attacks will surface.
- **CI/CD**: automated pipelines that build, test, and scan code on every
  change (e.g., GitHub Actions).

## Protocol terms (both tracks need these)

- **Modbus TCP**: a simple industrial protocol for reading/writing "registers"
  (numeric values) over a network — the easiest telemetry format to start
  with.
- **DNP3**: a more complex industrial protocol, the real standard used by
  North American utility SCADA systems — a stretch goal beyond Modbus.
EOF

# ---------------------------------------------------------------------------
# docs/01-project-scope.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/01-project-scope.md" <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# docs/02-architecture.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/02-architecture.md" <<'EOF'
# Architecture & Tech Stack

## High-level flow

```
[Grid Simulation Engine]  -->  [Protocol Emulator]  -->  [Cloud Ingestion]  -->  [Time-Series DB]
   (pandapower/OpenDSS,          (Modbus TCP / DNP3          (ingestion              (InfluxDB/
    IEEE test feeder)             over a simulated OT link)   service)                TimescaleDB)
                                                                    |
                                                                    v
                                                       [Monitoring/Dashboard] (Grafana)
                                                                    |
                                                                    v
                                                       [IDS / Anomaly Detection] (Suricata/Zeek + stats/ML)
                                                                    |
                                                                    v
                                                       [Alerting + SIEM] (Wazuh/ELK)

[Attack Simulator] --injects false data / floods / MITM--> targets the Protocol Emulator <-> Cloud link
```

The boundary between the Protocol Emulator and Cloud Ingestion is the
simulated OT/IT boundary — enforce real network segmentation and (ideally)
TLS/mTLS there, since that's where attacks get injected and detected.

## Tech stack

**Grid simulation (Power track)**
- `pandapower` (Python) — primary recommendation for distribution feeders
- `OpenDSS` (via `py-dss-interface` or `OpenDSSDirect.py`) — alternative,
  industry-standard, ships official IEEE test feeder files
- MATLAB/Simulink or MATPOWER — optional cross-validation
- Test feeder: IEEE 13-bus or 34-bus distribution feeder

**Protocol emulation (Power track)**
- `pymodbus` for Modbus TCP (starting point)
- `pydnp3`/`opendnp3` for DNP3 (stretch goal, more realistic)

**Cloud/infra (DevSecOps track)**
- AWS (free tier) with Terraform for IaC — or Azure/GCP if credits available
- Docker for containers; ECS/Fargate or a small EKS/managed Kubernetes
  cluster for orchestration

**Pipeline & storage (DevSecOps track)**
- MQTT or a lightweight queue (RabbitMQ/Kafka) into InfluxDB or TimescaleDB

**Observability (DevSecOps track)**
- Grafana for dashboards, Prometheus for infra metrics

**Security stack (DevSecOps track)**
- CI/CD: GitHub Actions with Bandit (Python SAST), Trivy (container
  scanning), Gitleaks (secrets scanning)
- IDS: Suricata or Zeek on the simulated OT network segment
- SIEM: Wazuh (open-source, ICS-friendly) or ELK stack
- Secrets: AWS Secrets Manager or HashiCorp Vault
EOF

# ---------------------------------------------------------------------------
# docs/03-timeline.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/03-timeline.md" <<'EOF'
# Timeline

| Weeks | Milestone | Power track | DevSecOps track |
|---|---|---|---|
| 1–2 | Foundations | Grid model running, validated against published results | Cloud skeleton + fake-data dashboard live |
| 3–4 | Telemetry pipeline | Modbus server exposing live simulation output | Real ingestion pipeline connected end-to-end |
| 5–7 | Security layer | Bad-data baseline + FDIA attack scenarios (naive and stealthy) | IDS/SIEM deployed, anomaly detection live, network segmentation + mTLS in place |
| 8–10 | Red/blue exercise & polish | Run attacks against full pipeline, document results | Tune detection against real attacks, finalize dashboard |

**Integration checkpoints** (see `docs/04-integration-checkpoints.md`) happen
at the end of week 4 (first telemetry handoff) and throughout weeks 5–10
(joint attack/defense runs).
EOF

# ---------------------------------------------------------------------------
# docs/04-integration-checkpoints.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/04-integration-checkpoints.md" <<'EOF'
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
against the live feed.

**DevSecOps track confirms:** the IDS/anomaly detection layer catches it, and
an alert appears in the SIEM.

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
EOF

# ---------------------------------------------------------------------------
# docs/05-attack-log-template.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/05-attack-log-template.md" <<'EOF'
# Attack/Defense Run Log

Copy this template for every attack scenario you run against the full
pipeline. Keep every entry — the pattern across runs is what makes the final
write-up compelling.

---

## Run #___

- **Date:**
- **Attack type:** (naive FDIA / stealthy FDIA / DoS flood / MITM-replay / other)
- **Target measurement(s):**
- **Description of the injected falsification:**

### Result

- **Detected?** yes / no
- **Detection method that caught it (if any):** (IDS rule / anomaly
  detection / SIEM correlation / not detected)
- **Time to detection:**
- **False positives triggered alongside it?**

### Grid-side impact if undetected

- What would a grid operator have concluded from the falsified data?
- What decision might have been made incorrectly as a result?

### Notes / follow-up

-
EOF

# ---------------------------------------------------------------------------
# docs/power-track/study-guide.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/power-track/study-guide.md" <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# docs/power-track/execution-plan.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/power-track/execution-plan.md" <<'EOF'
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
EOF

# ---------------------------------------------------------------------------
# docs/devsecops-track/study-guide.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/devsecops-track/study-guide.md" <<'EOF'
# Study Guide — DevSecOps Track

## Your role

Own the infrastructure and the defenses: the cloud pipeline that ingests the
Power track's telemetry, the monitoring layer, and the detection/response
systems that catch the attacks designed against it.

## Study order

### Phase 1 (weeks 1–2): Cloud & IaC fundamentals
- Chosen cloud provider fundamentals (if AWS: IAM, VPC, EC2/ECS/Fargate, S3)
- Terraform basics: providers, resources, state, plan/apply workflow
- Docker basics: images, containers, Dockerfiles, Compose

### Phase 2 (weeks 3–4): Pipeline & observability
- Message queues (MQTT/RabbitMQ/Kafka) — enough to pick one and get data
  flowing through it
- Time-series databases (InfluxDB or TimescaleDB) — schema design for
  telemetry data
- Grafana + Prometheus: dashboards and infra metrics

### Phase 3 (weeks 5–7): Security layer — the core content
- Network segmentation concepts, specifically the Purdue Model used in real
  ICS/OT security, and how to approximate it with VPC subnets/security groups
- IDS fundamentals: Suricata or Zeek, writing detection rules for
  Modbus/DNP3-style traffic
- SIEM fundamentals: Wazuh or the ELK stack — log aggregation, alerting
  workflows
- Basic anomaly detection: statistical methods (z-score, moving-window
  thresholds) as a first pass before reaching for ML
- mTLS and secrets management (AWS Secrets Manager or Vault)

### Phase 4 (weeks 8–10): CI/CD security & polish
- SAST/DAST/container/secrets scanning tools (Bandit, Trivy, Gitleaks) wired
  into GitHub Actions
- Tuning detection rules against real attack runs from the Power track

## Self-check

- [ ] Can stand up infra from a single `terraform apply` from scratch
- [ ] Have a working dashboard showing live (or synthetic) telemetry
- [ ] Have network segmentation between the "OT" and "cloud" zones
- [ ] Can demonstrate an IDS rule firing on suspicious traffic
- [ ] Have a SIEM alert pipeline that fires end-to-end on a test event
- [ ] Have a documented incident/detection log format ready for real runs
EOF

# ---------------------------------------------------------------------------
# docs/devsecops-track/execution-plan.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/docs/devsecops-track/execution-plan.md" <<'EOF'
# Execution Plan — DevSecOps Track

1. **Environment setup** — cloud account, Terraform + Docker installed,
   GitHub repo with branch protection and a basic CI pipeline.
   *Done when:* an empty `terraform apply` runs cleanly against your account.

2. **Base infrastructure** — VPC with segmented subnets (an "OT" zone and a
   "cloud" zone), least-privilege IAM roles.
   *Done when:* the segmentation is visible in the cloud console/Terraform
   plan, not just conceptual.

3. **Fake-data pipeline (unblock early)** — stand up the time-series DB and
   Grafana with a synthetic data generator, before real telemetry exists.
   *Done when:* a dashboard shows live-updating fake grid data.

4. **Real ingestion service** — build the service that polls/listens to the
   Power track's Modbus emulator and writes into the time-series DB.
   *Done when:* it can read a locally-run Modbus test server correctly.

   **→ Integration checkpoint 1 with Power track — see
   `docs/04-integration-checkpoints.md`.**

5. **Monitoring dashboards** — Grafana panels for grid state (voltage,
   current, power) fed by real telemetry.
   *Done when:* the dashboard updates live as the Power track's simulation
   runs.

6. **Security layer** — deploy Suricata/Zeek on the OT-to-cloud link, write
   initial detection rules; build a first-pass anomaly detector (statistical)
   on the telemetry stream; wire alerts into Wazuh/SIEM.
   *Done when:* a manually-injected bad value triggers an end-to-end alert.

7. **Network hardening** — enforce mTLS between services, move secrets into
   Secrets Manager/Vault.
   *Done when:* no credentials exist in plaintext anywhere in the repo or
   infra config.

8. **Joint red/blue exercise** — receive attack scenarios from the Power
   track, measure detection rate and time-to-detect, tune rules/thresholds.
   Log every run using `docs/05-attack-log-template.md`.

9. **CI/CD security polish** — SAST/container/secrets scanning wired into
   GitHub Actions across the whole repo.

10. **Write-up** — architecture, infra decisions, detection results, lessons
    learned.
EOF

# ---------------------------------------------------------------------------
# power-sim/README.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/power-sim/README.md" <<'EOF'
# power-sim/

Power Systems track source code lives here: grid model definitions,
time-series simulation scripts, the Modbus telemetry server, the bad-data
baseline detector, and FDIA attack scripts.

See `../docs/power-track/execution-plan.md` for the build order.
EOF

# ---------------------------------------------------------------------------
# infra/README.md
# ---------------------------------------------------------------------------
cat > "${ROOT}/infra/README.md" <<'EOF'
# infra/

DevSecOps track source lives here: Terraform configs, ingestion service code,
dashboard provisioning, IDS rules, and SIEM configuration.

See `../docs/devsecops-track/execution-plan.md` for the build order.
EOF

# ---------------------------------------------------------------------------
# .gitignore
# ---------------------------------------------------------------------------
cat > "${ROOT}/.gitignore" <<'EOF'
# Python
__pycache__/
*.pyc
.venv/
venv/

# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars

# Secrets
*.env
.env

# OS
.DS_Store
EOF

echo ""
echo "Done. Structure created:"
find "${ROOT}" -type f | sort

echo ""
echo "Next steps:"
echo "  1. cd ${ROOT}"
echo "  2. git init && git add . && git commit -m 'Scaffold GridGuard docs'"
echo "  3. Start with docs/01-project-scope.md, then each person opens their track's study-guide.md"