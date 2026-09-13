# Security Assurance Controls

This document records the controls that are enforced by the repository, why
they exist, and the work that remains account-side. It is the review checklist
for dependency, workflow, protocol, container, and infrastructure changes.

## Enforced Controls

| Surface | Control | Enforcement |
| --- | --- | --- |
| Repository | LF endings, final newlines, no trailing whitespace, no ignored tracked files, 5 MiB file cap | `make hygiene` |
| Documentation | Balanced fences, valid relative links, valid and responsive SVG roots | `make docs` |
| Python | 3.12/3.14 CI matrix, compilation, Ruff, Bandit, dependency audit, tests, 80% aggregate coverage | `make python` and CI |
| Workflows | actionlint 1.7.7 with verified archive checksum, yamllint, immutable action SHAs, explicit permissions, no `pull_request_target` | `make workflows` |
| Modbus | Valid request bounds, matching transaction/protocol/unit fields, exact bounded MBAP length, exact PDU byte count | Python tests |
| HTTP ingestion | 1 MiB snapshot ceiling, 4 KiB error-body ceiling, line-protocol escaping | Python tests |
| Containers | Immutable bases, non-root application users, dropped capabilities, no privilege escalation, read-only application filesystems, PID/memory/CPU limits | Docker and Compose validation |
| Networks | Loopback-only host ports and an internal OT simulation network | Compose validation and smoke tests |
| Images | Fixed high/critical findings reported; every known critical finding blocks CI | Trivy image scans |
| Terraform | Format, offline initialization, validation, and mocked native tests | `make terraform` |
| CloudFormation | Parsed templates plus exact OIDC trust, state-write, and action-boundary assertions | `make cloudformation` |
| Deployment | Manual sandbox-only Terraform plan, exact-environment OIDC trust, plan-only permissions boundary, remote encrypted state, no apply path | Deploy workflow |
| Image evidence | Exact runnable ECR digests, pull-only OIDC role, SPDX SBOM, complete high/critical scan, GitHub-signed attestation | Manual evidence workflow |

The required `CI Gate` aggregates every CI job and fails on either a failed or
cancelled dependency. Branch protection requires that single current check.

## Immutable Dependency Policy

GitHub Actions use complete 40-character commit SHAs with a nearby release tag
comment for reviewability. Dockerfiles use a human-readable version tag plus a
complete multi-platform manifest digest. Direct runtime Python requirements and
CI tools use exact versions; pip-audit resolves and audits their dependency
graphs. Dependabot monitors all three surfaces weekly.

For an update:

1. Resolve the release tag from the official upstream repository or registry.
2. Verify the commit or manifest-list digest independently.
3. Run dependency, image, and functional tests against that exact revision.
4. Update code, Terraform defaults, examples, and diagrams in the same change.
5. Merge only after the protected `CI Gate` passes.

Never replace a digest with a floating tag to work around an update failure.

## Vulnerability Policy

The filesystem scan blocks fixed high and critical dependency or
misconfiguration findings. Built-image scans report fixed high and critical
findings and block every known critical finding, including findings without an
available vendor fix. The high image findings remain visible because upstream
observability images can bundle tools that GridGuard does not execute; each
update still requires review of reachability and a scan comparison. No
vulnerability is silently ignored in a repository allow-list.

The current local stack uses InfluxDB 2.9.1 Alpine and Grafana 12.4.10. Their
manifest digests are recorded directly in Dockerfiles, Compose defaults, and
`.env.example`. Application images use digest-pinned Python slim bases.

The first AWS scan and subsequent patched candidates are covered by the
[container remediation record](deployment-records/2026-09-13-container-remediation.md).
It records the scanner discrepancy, fixed operating-system packages, unresolved
findings compiled into vendor Go binaries, and the resulting runtime block.

## Runtime Boundaries

The Compose OT simulation network is internal. Only InfluxDB and Grafana
publish ports, and both bind to `127.0.0.1`; the cloud-core bridge remains
non-internal because Docker suppresses host port publishing on internal
networks. Application containers use read-only root filesystems and writable
in-memory `/tmp`; every service drops Linux capabilities, forbids privilege
escalation, uses an init process, and has resource ceilings. InfluxDB runs as
its image-defined UID 1000.

The AWS root preserves the same architectural invariant: the Modbus ingestor
is the only workload permitted to initiate traffic to the simulator, and OT
route tables have no default route. Runtime resources remain disabled by
default, so repository validation never creates cloud resources.

## Residual Work

The state backend, cost budget, anomaly monitor, MFA-gated foundation role,
permissions boundary, default-off AWS foundation, and immutable-subject OIDC
plan role are deployed. The protected GitHub environment produced a no-change
remote plan using short-lived credentials. A separate least-privilege runtime
deployment policy, environment approval, secrets, and the private operator
access path remain blocked from runtime enablement. Registry-side SBOM
attestation, image signing, and provenance verification become enforceable only
after the signing identity exists.

The remediated ECR image digests and scans are recorded, and ECS task
definitions are pinned to the verified runnable manifests. A separately
bounded, manual signed-SBOM workflow and its read-only ECR role are prepared;
their local verification and the current finding delta are captured in the
[image-evidence readiness record](deployment-records/2026-09-13-image-evidence-readiness.md).
The role still needs an owner-reviewed CloudFormation deployment and a
successful evidence run. Runtime remains blocked pending the documented high
finding decision.
