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
   *Current implementation:* see `docs/07-local-fake-data-pipeline.md`.

4. **Real ingestion service** — build the service that polls/listens to the
   Power track's Modbus emulator and writes into the time-series DB.
   *Done when:* it can read a locally-run Modbus test server correctly.
   *Current implementation:* receiver-side contract and fixture profile live in
   `docs/08-modbus-handoff-contract.md`; validate the pre-handoff path with
   `make modbus-contracts`, `make stack-modbus-up`, and
   `make stack-modbus-smoke`.

   **→ Integration checkpoint 1 with Power track — see
   `docs/04-integration-checkpoints.md`.**

5. **Monitoring dashboards** — Grafana panels for grid state (voltage,
   current, power) fed by real telemetry.
   *Done when:* the dashboard updates live as the Power track's simulation
   runs.
   *Current implementation:* the local Grafana dashboard includes source,
   scenario, and feeder filters plus alert guardrails for attack flags,
   voltage envelope breaches, and stale telemetry. Validate with
   `make stack-dashboard-smoke`.

6. **Security layer** — deploy Suricata/Zeek on the OT-to-cloud link, write
   initial detection rules; build a first-pass anomaly detector (statistical)
   on the telemetry stream; wire alerts into Wazuh/SIEM.
   *Done when:* a manually-injected bad value triggers an end-to-end alert.
   *Current prep:* detector outputs should write `grid_detection` using
   `docs/09-detection-output-contract.md`.

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
