# Deliverable Traceability

This matrix prevents implementation, documentation, and evidence from being
conflated. A deliverable is complete only when all three are present. Roadmap
ideas are recorded separately and are not presented as delivered controls.

| Promise | Source | Implementation | Evidence | Status |
| --- | --- | --- | --- | --- |
| Standard feeder solved with time-varying load and PV | Project scope and Power track | `pandapower` balanced IEEE 13-node approximation and deterministic profile | Unit tests and local/cloud telemetry runs | Complete within documented balanced-model scope |
| Live industrial telemetry handoff | README and integration checkpoint 1 | Modbus TCP simulator, register map, receiver-side ingestor | Local smoke tests and AWS runtime logs | Complete |
| Time-series storage and live dashboard | Project deliverable 1 | InfluxDB, provisioned Grafana dashboard, alert rules | Automated panel/query smoke tests and six cloud UI captures | Complete |
| Naive and stealthy FDIA scenarios | Project deliverable 3 | Deterministic `naive-bad-value` and `stealthy-fdia` replays | Local attack records plus EKS detector and UI evidence | Complete within documented detector limits |
| OT/cloud network segmentation | Scope guardrail and DevSecOps plan | Docker networks, AWS subnet/security-group model, EKS namespaces and policies | Local/AWS evidence plus EKS allow/deny probes | Complete |
| Single real cloud Kubernetes cluster | Submission requirement | EKS Terraform root and digest-pinned manifests | Live EKS inventory, two private workers, and policy evidence | Complete; teardown remains |
| Reproducible infrastructure as code | Project deliverable 4 | Terraform, CloudFormation bootstraps, Kubernetes manifests | CI validation, reviewed plan checksums, and zero-drift plan | Complete |
| CI/CD security gates | Project deliverable | SAST, SCA, IaC, container, secret, workflow, and Kubernetes policy checks | Required GitHub `CI Gate` and CodeQL | Complete |
| Cloud secret management | DevSecOps plan | AWS Secrets Manager for ECS; ephemeral Kubernetes Secrets from ignored input | API metadata and EKS execution without secret values | Complete |
| Kubernetes default-deny enforcement | Submission requirement | VPC CNI strict mode and namespace policies | Positive and negative live probes | Complete |
| IDS and external SIEM | Timeline and DevSecOps plan | Application detectors and Grafana alerts only | Detector rows and dashboard smoke tests | Deferred roadmap; not an external IDS/SIEM |
| Service-to-service mTLS | Timeline and roadmap | Not implemented | None | Deferred roadmap; must not be claimed |
| Cloud runtime lifecycle | AWS handoff | ECS/Fargate runtime created and removed | Checksummed API/console evidence and zero drift | Complete with documented duration deviation |
| Final technical report | Project deliverable 5 | Sanitized records, diagrams, and verified UI captures | Versioned report source, PDF, and evidence index | Complete |

## Completion Rule

Submission readiness requires every row marked `Pending` or `Partial` to be
completed or explicitly accepted as a documented scope decision by the owner.
Items marked `Deferred roadmap` remain visible and must not appear in the final
report as implemented controls.
