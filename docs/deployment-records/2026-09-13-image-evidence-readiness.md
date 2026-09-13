# Signed Image Evidence Readiness Record

This record captures the local verification and repository controls prepared
for signed SBOM evidence on 2026-09-13. It is a readiness record, not evidence
that the AWS role or GitHub workflow has been deployed or executed.
The scanned images were built from commit
`00caa5fc8d810471a418972bdbdbe57875b307a6`.

## Exact Subjects

Docker's local content store contained the four OCI indexes published to ECR.
Both the parent index descriptor and the selected Linux/AMD64 manifest
descriptor matched the publication record before scanning.

| Component | Parent index digest | Attestation subject: Linux/AMD64 digest |
| --- | --- | --- |
| Power simulator | `sha256:3c04e4c78b0321108552366491fc451558397251307c30a55183475f6d14fc32` | `sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451` |
| Modbus ingestor | `sha256:6b568d28e9585f1712a398692bf7c59ca1a57cd83a2ea43816032691ddcf103b` | `sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7` |
| InfluxDB | `sha256:9ad78d3401ad36071a242404b33577be9b57415e6c5ad86db7bba77851e93bd9` | `sha256:66e4f468821b9a47f9eb0808d2e87c70d6ddd92c741450e9d78eff70ae856d67` |
| Grafana | `sha256:13bf0a41e63765a3ddd515f90f5a1e10ab095a040e05751c3d039f5ac37c1f91` | `sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c` |

The runnable digests, not the parent indexes or mutable tags, are the subjects
used by the signed-attestation workflow and by the Terraform task definitions.

## Tool And Database Snapshot

- Syft `1.51.1`, container index digest
  `sha256:95fe0835e5bebc6f8b1f8acef68d47d63d594ef4c0f25c097ff853b23cbac74c`.
- Trivy `0.74.0`, container index digest
  `sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969`.
- Trivy database schema `2`, updated `2026-09-13T13:10:01Z` and downloaded
  `2026-09-13T17:17:15Z`.
- Scans included fixed and unfixed `HIGH` and `CRITICAL` findings. No ignore
  file or vulnerability exception was used.

Syft generated valid SPDX 2.3 JSON for all subjects. Package counts were 123
for the power simulator, 96 for the Modbus ingestor, 350 for InfluxDB, and 600
for Grafana. Each document was below GitHub's 16 MiB SBOM-attestation limit.

## Fresh Vulnerability Result

| Image | Critical records | High records | Unique highs | Fixed unique highs | Unfixed unique highs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Power simulator | 0 | 46 | 10 | 2 | 8 |
| Modbus ingestor | 0 | 44 | 8 | 0 | 8 |
| InfluxDB | 0 | 70 | 41 | 40 | 1 |
| Grafana | 0 | 5 | 5 | 5 | 0 |

The eight unfixed Debian highs shared by the Python images are
`CVE-2025-69720`, `CVE-2026-16742`, `CVE-2026-54369`, `CVE-2026-76642`,
`CVE-2026-78408`, `CVE-2026-78409`, `CVE-2026-78410`, and `CVE-2026-9538`.
The increased count relative to the earlier Trivy 0.70.0 scan reflects the
newer vulnerability database, not image drift. Multiple installed packages can
map to one Debian source-package CVE, which is why 8 unique issues produce 44
records.

The power image's two fixed Python findings still originate from superseded
base-layer metadata. Runtime inspection found `msgpack 1.2.1` and no installed
`setuptools`, matching the earlier remediation record. This observation does
not suppress the raw scan records.

InfluxDB has 40 unique fixed highs compiled into the vendor-provided `influxd`,
`influx`, and `dasel` binaries. Its only unfixed unique high is
`CVE-2026-46377` in `dasel`. Grafana has five unique fixed highs compiled into
its vendor binary: `CVE-2026-21728`, `CVE-2026-28377`, `CVE-2026-43871`,
`CVE-2026-84304`, and `CVE-2026-84445`.

## Repository Control Prepared

The manual `image-evidence.yml` workflow:

1. Uses the protected `sandbox` environment and a dedicated OIDC role.
2. Pulls only the four exact runnable ECR digests.
3. Verifies the digest-qualified Docker repository reference and the selected
   Linux/AMD64 platform before scanning.
4. Logs out of ECR and clears temporary AWS credentials before third-party
   analysis actions run.
5. Generates SPDX JSON with pinned Syft 1.51.1.
6. Generates complete high/critical JSON with pinned Trivy 0.74.0 and fails on
   any critical finding.
7. Signs and stores an SPDX SBOM attestation with GitHub's official attestation
   action, validates the Sigstore bundle structure, and retains four plainly
   named files per component for 90 days: SBOM, scan, summary, and attestation.

The supporting CloudFormation role can only authenticate to ECR, read image
metadata, and download layers from the four named repositories. Its sole
policy is also its permissions boundary. Explicit denies cover all publication
and deletion operations used by this project, secret access, role passing, and
role chaining.

## Decision And Next Gate

Runtime remains blocked. Zero critical findings satisfies the automated image
gate, but it is not a blanket approval of the high findings. The remaining
cloud work is to deploy the reviewed two-resource evidence-role stack, add its
ARN as `AWS_IMAGE_EVIDENCE_ROLE_TO_ASSUME` in the protected `sandbox`
environment, run the workflow from merged `main`, and preserve the successful
run URL and four attestation IDs in a completion record.

After signed evidence exists, the next engineering decision is still the
CVE-by-CVE reachability review or fixed upstream releases described in the
[container remediation record](2026-09-13-container-remediation.md).
