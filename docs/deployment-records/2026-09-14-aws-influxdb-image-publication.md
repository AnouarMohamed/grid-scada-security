# AWS InfluxDB Image Publication Record

This record captures the publication of the hardened GridGuard InfluxDB image
to AWS account `227755136916` in `us-east-1` on 2026-09-14. The image was built
from merged commit `c39ed69`. No credentials, secret values, or temporary
authorization tokens are recorded here.

## Pre-Publication Gates

- The release image was rebuilt from a clean merged `main` worktree.
- The vendor entrypoint completed first-boot setup with `dasel` 3.11.2, and
  `influx ping` confirmed the initialized service was healthy.
- Trivy 0.74.0 scanned the exact final candidate at 2026-09-14 00:55:17Z,
  including findings with and without a vendor fix.
- The scan reported zero critical findings, 59 high records, 36 unique high
  CVEs, and zero unique findings without a published fix.
- The target tag did not exist before publication.
- An owner-reviewed CloudFormation change set temporarily added only the
  repository-scoped `OperatorEcrPublishPolicy`.

## Published OCI Artifact

The immutable tag identifies a BuildKit OCI index. ECS and the evidence
workflow use the runnable Linux/AMD64 digest, not the tag or parent index.

| Repository | Tag | Parent index digest | Runnable Linux/AMD64 digest | Provenance manifest digest | Pushed at | Size (bytes) |
| --- | --- | --- | --- | --- | --- | ---: |
| `gridguard-aws-sandbox/influxdb` | `2.9.1-gridguard.2` | `sha256:c9068f86b677578dcf51bf9fbc49dad025c3ebf62177471c5ed30b6aba49c8ee` | `sha256:359adac56f03b03f1b7072cc2d34bd0a49262e920961ed74cb490ea6a21d8fb0` | `sha256:81d4dc2996e7e371327a7010f73a753c4003663fc73edd0f731972d81ca50c13` | 2026-09-14 02:02:05 +01:00 | 95796607 |

ECR Basic scanning completed for the runnable manifest at 2026-09-14
02:02:15 +01:00 and returned no severity counts. That result does not
supersede Trivy's compiled Go binary analysis; the 36 unique high findings
remain visible and block runtime approval.

## Privilege And Runtime Cleanup

- A separately reviewed cleanup change set removed only
  `OperatorEcrPublishPolicy`.
- `gridguard-foundation-deployment` returned to `UPDATE_COMPLETE` with
  termination protection enabled and `EnableOperatorImagePublish=false`.
- The managed policy no longer exists, and `anouar-admin` has no attachment
  matching its former ARN.
- The immutable ECR tag and parent index remained present after cleanup.
- The ECS cluster remained `ACTIVE` with zero active services, zero running
  tasks, zero pending tasks, and empty service and task lists.
- Both local AWS CLI login profiles were logged out after verification; AWS
  access tokens already loaded by tools expire within 15 minutes.

## Release Decision

Terraform defaults and the signed-image evidence workflow select the exact
runnable digest above. The replacement
[signed-image evidence run](2026-09-14-signed-image-evidence.md) completed
successfully against that digest. The image is retained for evidence and future
rescans, but remains blocked from runtime use pending resolution or explicit
review of the documented vendor-binary findings.
