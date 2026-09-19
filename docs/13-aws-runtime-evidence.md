# AWS Runtime Evidence

This runbook captures a reproducible, checksummed record of a bounded GridGuard
AWS exercise. The collector makes read-only AWS API calls, refuses root and the
wrong account, and never requests a Secrets Manager secret value.

Raw CloudWatch events and AWS metadata may contain account identifiers, private
addresses, resource ARNs, and experiment details. They belong only under the
ignored `tmp/aws-runtime-evidence/` directory or in controlled offline storage.
Commit a sanitized result summary, not the raw archive.

## Before The Run

1. Confirm the [conditional InfluxDB risk acceptance](deployment-records/2026-09-19-influxdb-runtime-risk-acceptance.md)
   is unexpired and every activation condition still holds. Run the signed
   evidence workflow from current `main` less than 24 hours before activation:

   ```bash
   gh workflow run image-evidence.yml --ref main
   gh run watch --exit-status
   ```

   Record the successful run URL and confirm its InfluxDB summary reports zero
   Critical findings and no materially new reachable High finding.
2. Save and review the Terraform plan. Record its SHA-256 digest and exact Git
   commit in the change record before applying it.
3. Set the experiment start in UTC before starting any workload. Keep the total
   active runtime at or below eight hours.
4. Keep `grafana_public=false`, NAT disabled, production data absent, and all
   workloads pinned to the recorded runnable image digests.

## Automated Capture

Authenticate the non-root operator profile, then run the collector after the
experiment and before destroying runtime resources:

```bash
AWS_PROFILE=gridguard \
AWS_REGION=us-east-1 \
EVIDENCE_START_TIME=2026-09-20T09:00:00Z \
EVIDENCE_END_TIME=2026-09-20T12:00:00Z \
make aws-runtime-evidence
```

Use the real UTC timestamps. `EVIDENCE_END_TIME` defaults to the current time.
The command writes a private directory, a compressed archive, and its SHA-256
checksum under `tmp/aws-runtime-evidence/`. A nonzero exit means at least one
API capture failed; the successful files remain usable, but the run is not
complete until every line in `collection-errors.tsv` is resolved.

The archive contains:

- caller identity, AWS CLI version, Git commit, and working-tree state;
- ECS cluster, service, running/stopped task, and task-definition metadata;
- ECR image tags and digests for all four services;
- VPC, subnet, route-table, security-group, and endpoint state;
- Grafana load-balancer, target-group, and target-health state;
- service and VPC flow-log events bounded to the experiment window; and
- a manifest plus per-file SHA-256 inventory.

The collector records metadata and logs only. It does not change desired
counts, query secret values, invoke attacks, take screenshots, or destroy
resources.

## Human Evidence

Create a run record from the [attack/defense template](05-attack-log-template.md)
and capture these items while the private operator path is active:

1. Baseline Grafana dashboard with UTC time range and healthy telemetry.
2. Attack interval with the injected measurement visible.
3. Detector or alert output showing its timestamp, rule, severity, and result.
4. A sanitized InfluxDB query result supporting the same timestamps.
5. The reviewed Terraform plan checksum and apply completion result.
6. The evidence archive checksum printed by the collector.

Do not include passwords, tokens, cookies, authorization headers, secret
values, browser storage, or Terraform state in screenshots or committed notes.
Use UTC everywhere and preserve the original image files outside Git; the
sanitized run record should reference their filenames and checksums.

## Teardown Evidence

After capture, return all four desired counts to zero and apply the saved
shutdown plan. Run the collector a second time with a new `EVIDENCE_RUN_ID` and
the same experiment window. The shutdown record is acceptable only when it
shows zero running tasks, zero desired tasks, and no healthy Grafana target.

Keep the two archive checksums in the sanitized run record. Delete temporary
secret values and private tunnel/session material according to the AWS runbook,
then review billing and budget alerts. Do not delete the raw archives until the
final report and evidence integrity review are complete.
