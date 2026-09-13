# AWS Image Publication Record

This sanitized record captures the first GridGuard AWS sandbox image
publication. It intentionally omits the account number, IAM user, resource
identifiers unrelated to the images, and local credential configuration.

## Change Identity

| Field | Recorded value |
| --- | --- |
| Publication date | 2026-09-13 |
| Region | `us-east-1` |
| Repository revision | `5864ae1` |
| Temporary publisher policy | Exact four repositories; enabled only for publication |
| Runtime enabled | `false` |

## Published Images

| Repository | Tag | ECR manifest digest | Compressed size (bytes) |
| --- | --- | --- | ---: |
| `gridguard-aws-sandbox/power-sim` | `0.1.0` | `sha256:adbc099e6fb4e6b84681f12bb5fbfe13dbd1f0487ade203f2f8babec633fd831` | 151173962 |
| `gridguard-aws-sandbox/modbus-ingestor` | `0.1.0` | `sha256:a7d927f685fe87e9d903cb5e8e23888e4e239fbf91aec4fdcb7ab34b6a7f06a1` | 45477014 |
| `gridguard-aws-sandbox/influxdb` | `2.9.1` | `sha256:01c378d47f8f5300db6220ad82d84bb8555c485681d85bb2905d064db568a508` | 86769043 |
| `gridguard-aws-sandbox/grafana` | `12.4.10` | `sha256:5d45c9b8b4782ecd5e19af02df523f0cc43e9815322b95fc022d1c893625cf47` | 294009760 |

AWS ECR returned each digest after its push, and a separate `DescribeImages`
read confirmed the same tag-to-digest mapping. All four repositories reported
immutable tags and AES-256 encryption. The local Trivy release gate had already
reported zero fixed critical vulnerabilities for each image before publication.

## Publication Authorization

The CloudFormation change set added only `OperatorEcrPublishPolicy`. Its live
default version was verified before use: registry authentication plus the six
documented ECR image-push actions, four exact repository ARNs, and no wildcard,
deletion, or repository-administration action. Docker was reauthenticated only
after that verification.

## AWS Scan Evidence

Docker published each tag as an OCI index containing one runnable Linux/AMD64
manifest and one BuildKit attestation manifest. ECR basic scanning rejects the
parent index media type, but the repository scan-on-push setting scanned each
runnable child manifest successfully during publication.

| Image | Runnable manifest digest | Completed | Critical | High | Medium | Low |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `power-sim:0.1.0` | `sha256:17f387e6dc267bfcaa8e0bdf5562e9dc39323179c8b09d12623baab4e11f3fe5` | 2026-09-13 02:03:14 +01:00 | 4 | 16 | 9 | 2 |
| `modbus-ingestor:0.1.0` | `sha256:2eb0fc9031a9470e237fa3b8631eef039c4937f917e870cb0bbb15d309b7003f` | 2026-09-13 02:04:00 +01:00 | 4 | 16 | 9 | 2 |
| `influxdb:2.9.1` | `sha256:e34b3d2efc8fd2537c1c44b6bf1ef74533a2232126cf679ae0001a0de72d494f` | 2026-09-13 02:04:45 +01:00 | 12 | 32 | 8 | 0 |
| `grafana:12.4.10` | `sha256:47ff9956fb5a154f9fc062328bc2285a4972d14a49efbba8779824b60b3e43e0` | 2026-09-13 02:07:11 +01:00 | 4 | 14 | 1 | 0 |

These AWS counts include findings without an available fix. The separately
enforced local Trivy gate blocks fixed critical vulnerabilities and passed all
four images; a current Trivy reconciliation found no fixed version for any of
its critical results. The differing scanner databases and the AWS critical
findings still require documented reachability and fix-availability review
before runtime deployment.

The post-push review also found that the account-wide registry configuration
had no scan-on-push rule. A reviewed Terraform plan added one registry-level
`BASIC` `SCAN_ON_PUSH` rule scoped to `gridguard-aws-sandbox/*`; the post-apply
plan reported no drift. This makes scanning explicit for future repositories
and images instead of relying only on the older per-repository setting.

## Completed Cleanup

The cleanup CloudFormation change set set `EnableOperatorImagePublish` back to
`false` and removed only `OperatorEcrPublishPolicy`. The stack reached
`UPDATE_COMPLETE`; API checks confirmed that the resource, managed policy, and
user attachment were absent. Docker's cached ECR credential was removed with
`docker logout`. ECS still reported zero running tasks, zero pending tasks, and
zero active services.
