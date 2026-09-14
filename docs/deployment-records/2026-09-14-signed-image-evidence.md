# Replacement Signed Image Evidence Record

This record captures the signed-SBOM evidence run after publishing the hardened
InfluxDB `2.9.1-gridguard.2` image. It supersedes the InfluxDB subject in the
[original completion record](2026-09-13-signed-image-evidence.md); it does not
approve the ECS runtime.

## Successful Run

[Run 34795532609](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/34795532609)
started from merged `main` commit
`49730b1022dcf8edbac50c9e83eaa1ac293e8f27` at `2026-09-14T01:19:08Z` and
completed successfully at `2026-09-14T01:22:24Z`. Each matrix job:

1. Assumed the dedicated pull-only AWS role through the protected `sandbox`
   environment and exact-repository OIDC trust.
2. Pulled and verified its digest-qualified Linux/AMD64 ECR subject.
3. Removed ECR and temporary AWS credentials before evidence generation.
4. Generated an SPDX 2.3 JSON SBOM with Syft 1.51.1.
5. Scanned fixed and unfixed high and critical findings with Trivy 0.74.0.
6. Created a GitHub-signed SBOM attestation and validated its Sigstore bundle.
7. Uploaded the four-file evidence artifact and enforced zero critical findings.

## Subjects And Artifacts

The attestation subjects are runnable manifests, not OCI indexes or tags. All
artifacts expire on `2026-12-13T01:19:09Z` under 90-day retention.

| Component | Job ID | Artifact ID | Runnable subject | Attestation |
| --- | ---: | ---: | --- | --- |
| Power simulator | `103827765595` | `10329053896` | `sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451` | [47229561](https://github.com/AnouarMohamed/grid-scada-security/attestations/47229561) |
| Modbus ingestor | `103827765658` | `10329413184` | `sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7` | [47229565](https://github.com/AnouarMohamed/grid-scada-security/attestations/47229565) |
| InfluxDB | `103827765473` | `10329248556` | `sha256:359adac56f03b03f1b7072cc2d34bd0a49262e920961ed74cb490ea6a21d8fb0` | [47229531](https://github.com/AnouarMohamed/grid-scada-security/attestations/47229531) |
| Grafana | `103827765640` | `10329392247` | `sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c` | [47229826](https://github.com/AnouarMohamed/grid-scada-security/attestations/47229826) |

| Component | Artifact name | Compressed bytes |
| --- | --- | ---: |
| Power simulator | `image-evidence-power-sim-34795532609` | 883508 |
| Modbus ingestor | `image-evidence-modbus-ingestor-34795532609` | 822763 |
| InfluxDB | `image-evidence-influxdb-34795532609` | 477341 |
| Grafana | `image-evidence-grafana-34795532609` | 543576 |

Each downloaded artifact contained exactly the component's attestation, SPDX
SBOM, scan summary, and complete Trivy JSON report at its top level.

## Evidence Checksums

These SHA-256 values identify the downloaded files independently of GitHub's
compressed artifact archives.

| Component | Attestation JSON | SPDX JSON |
| --- | --- | --- |
| Power simulator | `3e7eb4b5775f48f619a2925d127df2bcff320f26fd673c7a3b7a6f358a160c42` | `0673791452b098d997f1b787913507ebd247495605b335ea3422b1ca94e8cdbd` |
| Modbus ingestor | `b1497ce0502a6fe41aa0846dfe31e99ee5eaf089e1fa780545ed5963a8064491` | `c60ea8b2d4d6fe5b336c410e7ada77d2ae0ee89f92fc25744753c082be0bb43c` |
| InfluxDB | `4ea0051a9daac07a6ad3d59823b5474c3238412140bd6d3d7e6607eb08c49c90` | `54157457a3c701811bf824b90494442a4e2efb3ce4af6995e395f577959598d3` |
| Grafana | `1c56d3c354b997a09743fc892a92ec344078b596e5c6e2ae463fc39e5730edac` | `318cfdf69a3ab4e364d86b3b47dbe22485b9bc0a5449c7a1372f80e134dfe2af` |

| Component | Summary JSON | Trivy JSON |
| --- | --- | --- |
| Power simulator | `2fa8292550d221457cffc57f8a25b6132e103bbc3ece73d581e77bcd026a42c0` | `bc4ff9a1bc387cb6dce3525336279b7569c8b1ac1f93493644d8208ef7e46da5` |
| Modbus ingestor | `1d0cecf0c2ca44344761d8cb683d9726e5759072a50f202b7fd7d3841884849f` | `8d823ecf8fee6e3db35939d862c0a3291cded221586744d0210fd261aa52deaa` |
| InfluxDB | `c0c8f081eb5cab743b3f2da19d4c4c5649839baf14db814fcb014c63591c040d` | `74ae8b35a1e3cc8c3d03aea1372de828f23211bb3916da7ac41455db375c4ef0` |
| Grafana | `0d77b044e81e4c2fe7f80797aba43e9ae7c4d9832200339e7333836db5dfd42e` | `efbb792c8201e0c90021f7be9b057def25fc68b7510ce806e6784450684ee05a` |

## Scan Result

| Image | Critical records | High records | Unique highs | Fixed unique highs | Unfixed unique highs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Power simulator | 0 | 46 | 10 | 2 | 8 |
| Modbus ingestor | 0 | 44 | 8 | 0 | 8 |
| InfluxDB | 0 | 59 | 36 | 36 | 0 |
| Grafana | 0 | 5 | 5 | 5 | 0 |

No ignore file or vulnerability exception was used. Compared with the original
signed run, InfluxDB removed 11 high records and five unique high CVEs without
introducing a new high CVE. The other three subjects and their results are
unchanged.

## Verification Boundary

Offline checks confirmed that every downloaded bundle has media type
`application/vnd.dev.sigstore.bundle.v0.3+json`, one DSSE signature, one
transparency-log entry, and a nonempty signing certificate. Every summary names
the exact merged commit and expected digest. GitHub's repository attestation
API returned one stored attestation for the new InfluxDB subject.

The workflow itself authenticated to private ECR, verified each pulled subject,
and signed it before credentials were removed. A separate registry-authenticated
`gh attestation verify` was intentionally not repeated after both local AWS
profiles were logged out. The original three unchanged subjects retain their
previous independent verification record.

## Decision And Next Gate

The replacement evidence gate is complete for the hardened InfluxDB subject.
Runtime remains disabled and blocked: all 36 unique InfluxDB high findings have
published fixes but remain compiled into required vendor binaries. The next
engineering gate is a fixed upstream InfluxDB release or an explicit,
time-bounded CVE-by-CVE risk decision before any ECS desired count becomes
nonzero.
