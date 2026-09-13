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

## Scan Follow-Up

The post-push check found that the account registry had `BASIC` scanning with
no scan-on-push rule. The older repository-level `scan_on_push` values therefore
did not produce scans for these images. Runtime remains disabled while the
repository correction adds a registry-level `BASIC` `SCAN_ON_PUSH` rule scoped
to `gridguard-aws-sandbox/*`. After applying that reviewed one-resource plan,
manually start each existing image scan and append the completed severity
counts to this record.

## Required Cleanup

Set `EnableOperatorImagePublish` back to `false` through a reviewed
CloudFormation change set that removes only `OperatorEcrPublishPolicy`. After
the stack reaches `UPDATE_COMPLETE`, verify that the policy no longer exists
or attaches to the operator and remove the cached registry credential with
`docker logout`.
