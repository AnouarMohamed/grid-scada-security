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
| Images | Fixed high/critical findings reported; fixed critical findings block CI | Trivy image scans |
| Terraform | Format, offline initialization, validation, and mocked native tests | `make terraform` |
| Deployment | Manual sandbox-only dispatch, protected environment, OIDC, remote encrypted state, apply from `main` only | Deploy workflow |

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
findings and block fixed critical findings. The high image findings remain
visible because upstream observability images can bundle tools that GridGuard
does not execute; each update still requires review of reachability and a scan
comparison. No vulnerability is silently ignored in a repository allow-list.

The current local stack uses InfluxDB 2.9.1 Alpine and Grafana 12.4.10. Their
manifest digests are recorded directly in Dockerfiles, Compose defaults, and
`.env.example`. Application images use digest-pinned Python slim bases.

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
permissions boundary, and default-off AWS foundation are deployed. The AWS
owner must still configure OIDC trust, a least-privilege runtime deployment
policy, environment approval, secrets, the private operator access path, and
reviewed image publication. Registry-side SBOM attestation, image signing, and
provenance verification become enforceable only after the target registry and
signing identity exist.

The next repository step after cloud bootstrap is to record the first reviewed
Terraform plan and ECR image digests, then add signed SBOM attestations to the
publication workflow.
