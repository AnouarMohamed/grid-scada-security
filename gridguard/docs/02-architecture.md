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
