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
