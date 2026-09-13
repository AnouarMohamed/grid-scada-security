# AWS Remediated Image Publication Record

This record captures the second GridGuard image publication to AWS account
`227755136916` in `us-east-1` on 2026-09-13. The images were built from merged
commit `00caa5f` after the remediation in pull request 42. It contains no
credentials, secret values, or temporary authorization tokens.

## Pre-Publication Gates

- All four release images were rebuilt from the merged `main` worktree.
- Trivy 0.70.0 reported zero critical findings for each exact release image,
  including findings without a vendor fix.
- ECR returned zero existing images for all four target tags before upload.
- The registry configuration was `BASIC` scanning with `SCAN_ON_PUSH` scoped to
  `gridguard-aws-sandbox/*`.
- The owner-reviewed enablement change set added only
  `OperatorEcrPublishPolicy`. Its document allowed registry authentication and
  the six required push actions on the four exact GridGuard repositories.

## Published OCI Artifacts

Each tag points to a BuildKit OCI index containing a runnable Linux/AMD64
manifest and a provenance-attestation manifest. The parent digest identifies
the complete pushed index; the runnable digest identifies the bytes ECS would
execute.

| Repository | Tag | Parent index digest | Runnable Linux/AMD64 digest | Pushed at | Size (bytes) |
| --- | --- | --- | --- | --- | ---: |
| `gridguard-aws-sandbox/power-sim` | `0.1.1` | `sha256:3c04e4c78b0321108552366491fc451558397251307c30a55183475f6d14fc32` | `sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451` | 2026-09-13 11:23:41 +01:00 | 164276051 |
| `gridguard-aws-sandbox/modbus-ingestor` | `0.1.1` | `sha256:6b568d28e9585f1712a398692bf7c59ca1a57cd83a2ea43816032691ddcf103b` | `sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7` | 2026-09-13 11:24:11 +01:00 | 57258040 |
| `gridguard-aws-sandbox/influxdb` | `2.9.1-gridguard.1` | `sha256:9ad78d3401ad36071a242404b33577be9b57415e6c5ad86db7bba77851e93bd9` | `sha256:66e4f468821b9a47f9eb0808d2e87c70d6ddd92c741450e9d78eff70ae856d67` | 2026-09-13 11:24:24 +01:00 | 91747375 |
| `gridguard-aws-sandbox/grafana` | `12.4.10-gridguard.1` | `sha256:13bf0a41e63765a3ddd515f90f5a1e10ab095a040e05751c3d039f5ac37c1f91` | `sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c` | 2026-09-13 11:24:29 +01:00 | 297363447 |

## ECR Scan Evidence

ECR Basic scanning completed automatically against each runnable manifest.
An omitted severity key in the AWS response represents zero findings.

| Image | Completed | Critical | High | Medium | Low |
| --- | --- | ---: | ---: | ---: | ---: |
| `power-sim:0.1.1` | 2026-09-13 11:23:52 +01:00 | 0 | 1 | 0 | 0 |
| `modbus-ingestor:0.1.1` | 2026-09-13 11:24:21 +01:00 | 0 | 1 | 0 | 0 |
| `influxdb:2.9.1-gridguard.1` | 2026-09-13 11:24:32 +01:00 | 0 | 0 | 0 | 0 |
| `grafana:12.4.10-gridguard.1` | 2026-09-13 11:24:42 +01:00 | 0 | 0 | 0 | 0 |

The Python-image high finding is `CVE-2026-85091` in Debian package `zlib`
version `1.3.dfsg+really1.3.1-1`. ECR assigned CVSS 4.0 score 8.3 and did not
report a fixed package version. The simulator and ingestor do not call the
affected non-blocking `gzwrite()` path, but the finding remains open pending a
Debian fix and rescan.

ECR Basic scanning returning no findings for InfluxDB and Grafana does not
supersede the deeper Trivy results for dependencies compiled into their Go
binaries. Those fixed high findings and their release block remain documented
in the [container remediation record](2026-09-13-container-remediation.md).

## Privilege And Runtime Cleanup

- The cleanup change set removed only `OperatorEcrPublishPolicy`.
- `gridguard-foundation-deployment` returned to `UPDATE_COMPLETE` with
  `EnableOperatorImagePublish=false`.
- The policy resource was absent from both the stack and IAM after cleanup.
- The root AWS CLI profile and the Docker ECR registry session were logged out.
- The ECS cluster remained `ACTIVE` with zero active services, zero running
  tasks, and zero pending tasks.
- A post-publication Terraform refresh and plan reported `No changes`.

## Release Decision

The four remediated images are retained under immutable tags for evidence and
rescan. Terraform task definitions are pinned to the verified runnable digests
above, but the images are not approved for runtime use. Before any ECS desired
count can become nonzero, close the vendor-binary decision in the remediation
record and review the open zlib finding.
