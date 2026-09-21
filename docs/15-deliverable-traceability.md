# Deliverable Traceability

This matrix prevents implementation, documentation, and evidence from being
conflated. A deliverable is complete only when all three are present. Roadmap
ideas are recorded separately and are not presented as delivered controls.

| Promise | Source | Implementation | Evidence | Status |
| --- | --- | --- | --- | --- |
| Standard feeder solved with time-varying load and PV | Project scope and Power track | Balanced IEEE 13-node approximation and deterministic profile | Unit tests and local telemetry runs | Partial: published-reference calibration remains |
| Live industrial telemetry handoff | README and integration checkpoint 1 | Modbus TCP simulator, register map, receiver-side ingestor | Local smoke tests and AWS runtime logs | Complete |
| Time-series storage and live dashboard | Project deliverable 1 | InfluxDB, provisioned Grafana dashboard, alert rules | Automated panel/query smoke tests | Partial: final UI screenshots pending |
| Naive and stealthy FDIA scenarios | Project deliverable 3 | Deterministic `naive-bad-value` and `stealthy-fdia` replays | Local attack records and detector smoke tests | Complete locally; EKS evidence pending |
| OT/cloud network segmentation | Scope guardrail and DevSecOps plan | Docker networks, AWS subnet/security-group model, EKS namespaces and policies | Local/AWS evidence plus EKS allow/deny probes | EKS cloud execution pending |
| Single real cloud Kubernetes cluster | Submission requirement | EKS Terraform root and digest-pinned manifests | Live EKS inventory and policy evidence | Pending deployment |
| Reproducible infrastructure as code | Project deliverable 4 | Terraform, CloudFormation bootstraps, Kubernetes manifests | CI validation and reviewed plan checksums | Complete for ECS; EKS apply pending |
| CI/CD security gates | Project deliverable | SAST, SCA, IaC, container, secret, workflow, and Kubernetes policy checks | Required GitHub `CI Gate` and CodeQL | Complete |
| Cloud secret management | DevSecOps plan | AWS Secrets Manager for ECS; ephemeral Kubernetes Secrets from ignored input | API metadata without secret values | Complete for ECS; EKS execution pending |
| Kubernetes default-deny enforcement | Submission requirement | VPC CNI strict mode and namespace policies | Positive and negative live probes | Pending deployment |
| IDS and external SIEM | Timeline and DevSecOps plan | Application detectors and Grafana alerts only | Detector rows and dashboard smoke tests | Deferred roadmap; not an external IDS/SIEM |
| Service-to-service mTLS | Timeline and roadmap | Not implemented | None | Deferred roadmap; must not be claimed |
| Cloud runtime lifecycle | AWS handoff | ECS/Fargate runtime created and removed | Checksummed API/console evidence and zero drift | Complete with documented duration deviation |
| Final technical report | Project deliverable 5 | Sanitized records and diagrams | PDF and final evidence index | Pending |

## Completion Rule

Submission readiness requires every row marked `Pending` or `Partial` to be
completed or explicitly accepted as a documented scope decision by the owner.
Items marked `Deferred roadmap` remain visible and must not appear in the final
report as implemented controls.

