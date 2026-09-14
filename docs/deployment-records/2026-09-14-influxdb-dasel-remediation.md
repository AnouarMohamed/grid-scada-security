# InfluxDB Dasel Remediation Record

This record captures the hardening and verification of the GridGuard InfluxDB
image. It reduces the signed-evidence scan findings without rebuilding the
InfluxDB product from source. The verified candidate was subsequently published
to ECR, but it is not approved for runtime use.

## Trigger And Scope

The canonical
[signed image evidence run](2026-09-13-signed-image-evidence.md) reported 70
high records across 41 unique CVEs in the InfluxDB image. The findings were
compiled into three vendor binaries:

| Binary | High records | Unique high CVEs | Runtime purpose |
| --- | ---: | ---: | --- |
| `/usr/local/bin/influxd` | 33 | 32 | Required database server |
| `/usr/local/bin/influx` | 16 | 16 | Initial setup and ECS health check |
| `/usr/local/bin/dasel` | 21 | 21 | Vendor entrypoint configuration parsing |

The three sets overlap, producing 41 unique CVEs rather than 70. InfluxDB
2.9.1 remains the current supported v2 image needed by the lab's Flux queries.
The official `2`, `2.9`, and `2.9.1` Alpine tags resolve to the same pinned
upstream index already used by GridGuard, so rebuilding the existing recipe
without changing a bundled binary cannot remediate the Go findings.

## Candidate Change

The upstream image bundles `dasel` 3.4.1. GridGuard now replaces it during the
existing package-upgrade layer with the official
[`dasel` 3.11.2 release](https://github.com/TomWright/dasel/releases/tag/v3.11.2).
The version is exact, the download fails on HTTP errors, and the compressed
release asset is verified before installation with an architecture-specific
SHA-256 value published in GitHub's release metadata:

| Architecture | Asset | SHA-256 |
| --- | --- | --- |
| Linux AMD64 | `dasel_linux_amd64.gz` | `1af4fc41087c91dd59ab10aa13dc66a87d291e26b24bdec51480fe96cfd3ccf1` |
| Linux ARM64 | `dasel_linux_arm64.gz` | `6f783edc1ff8e41c6bab901227740209506eecb6d67a87b3b7dda9e762c860a2` |

An unsupported Alpine architecture fails the build. Changing the version
without also supplying matching embedded checksums fails verification.

## Functional Verification

The final Linux/AMD64 candidate built from the pinned InfluxDB parent and
reported `dasel 3.11.2`. Its local OCI index ID was
`sha256:42e3cdeeba3debe48eb2f2d5706c23f84aac7977799529a63636684444b2844e`.
This local identifier is build evidence, not a release digest.

A clean disposable container exercised the vendor entrypoint's complete setup
path with temporary local-only credentials and anonymous storage:

1. The entrypoint parsed its default YAML configuration with the new `dasel`.
2. `influxd` initialized and returned `OK` from `influx ping`.
3. The `gridguard` organization and `gridguard_telemetry` bucket existed.
4. Container logs contained zero errors and two vendor deprecation warnings.
5. The container and its anonymous volume were forcibly removed after the
   test.

Hadolint 2.14.0 reported no Dockerfile findings.

## Fresh Scan Delta

Trivy 0.74.0 scanned the exact final candidate on 2026-09-14 at
`00:43:44Z`, including fixed and unfixed high and critical findings. No ignore
file or exception was used.

| Result | Published `gridguard.1` | Local `gridguard.2` candidate | Delta |
| --- | ---: | ---: | ---: |
| Critical records | 0 | 0 | 0 |
| High records | 70 | 59 | -11 |
| Unique high CVEs | 41 | 36 | -5 |
| Fixed unique highs | 40 | 36 | -4 |
| Unfixed unique highs | 1 | 0 | -1 |

No high CVE ID was introduced. The removed set is:

- `CVE-2026-32280`: Go certificate-chain construction denial of service.
- `CVE-2026-32281`: Go certificate-chain validation denial of service.
- `CVE-2026-32283`: Go TLS 1.3 key-update denial of service.
- `CVE-2026-46377`: `dasel` trailing-backslash selector panic, fixed in
  [GHSA-m5j3-4634-c2vq](https://github.com/TomWright/dasel/security/advisories/GHSA-m5j3-4634-c2vq).
- `CVE-2026-46378`: `dasel` unterminated-regex CPU loop, fixed in
  [GHSA-m6xr-fvfg-5g64](https://github.com/TomWright/dasel/security/advisories/GHSA-m6xr-fvfg-5g64).

The candidate's remaining high records are all reported as fixed upstream:

| Binary | High records | Unique high CVEs |
| --- | ---: | ---: |
| `/usr/local/bin/influxd` | 33 | 32 |
| `/usr/local/bin/influx` | 16 | 16 |
| `/usr/local/bin/dasel` | 10 | 10 |

`dasel` 3.11.2 is the latest official release, but it was built with Go 1.26.4
and `golang.org/x/text` 0.28.0; newer advisories now have fixes beyond those
versions. The latest official Influx CLI remains 2.8.0, which is already
bundled in the image. Replacing either tool with a locally rebuilt binary would
create a maintenance and provenance obligation that this change deliberately
does not accept.

## Publication

The candidate was rebuilt from merged commit `c39ed69` and published on
2026-09-14 as immutable tag `2.9.1-gridguard.2`. The exact ECR identifiers,
post-push scan, privilege cleanup, and inactive runtime verification are in the
[publication record](2026-09-14-aws-influxdb-image-publication.md).

## Decision And Next Gate

The candidate is a strict improvement and retains the supported vendor
entrypoint. Runtime remains blocked because 32 unique high CVEs are still
compiled into the required `influxd` server, while the required `influx` client
and `dasel` tool contain additional fixed findings.

Publication and the Terraform digest update do not approve runtime. The next
evidence gate is a successful manual signed-SBOM workflow against the new
runnable digest. The remaining server findings still require a fixed vendor
release or explicit, time-bounded CVE review before any desired count becomes
nonzero.
