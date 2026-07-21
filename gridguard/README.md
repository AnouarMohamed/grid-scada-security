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
