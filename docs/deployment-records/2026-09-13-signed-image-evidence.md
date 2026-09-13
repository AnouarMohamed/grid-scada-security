# Signed Image Evidence Completion Record

This record captures the successful signed-SBOM evidence run for the four
immutable GridGuard sandbox images on 2026-09-13. It records evidence
generation and identity verification; it is not approval to start the ECS
runtime.

## Control Plane

The `gridguard-github-image-evidence` CloudFormation stack is
`CREATE_COMPLETE` in AWS account `227755136916`, region `us-east-1`, with
termination protection enabled. Its only resources are:

- Role
  `arn:aws:iam::227755136916:role/gridguard/gridguard-aws-sandbox-github-image-evidence`.
- Managed policy
  `arn:aws:iam::227755136916:policy/gridguard/gridguard-aws-sandbox-github-image-evidence`.

The managed policy is both the role's sole attached policy and its permissions
boundary. The role trusts only the `sandbox` environment of repository
`AnouarMohamed/grid-scada-security`. Its exact trust subject is
`repo:AnouarMohamed@235483559/grid-scada-security@1307773501:environment:sandbox`,
which includes the immutable GitHub owner and repository IDs. Its permissions
permit ECR authentication and pull operations for the four exact GridGuard
repositories. Explicit denies cover image mutation and deletion, secret
access, role passing, and role chaining.

CloudFormation template validation succeeded, and IAM Access Analyzer returned
no findings for either the trust policy or permissions policy. The protected
GitHub `sandbox` environment contains the role ARN as the encrypted
`AWS_IMAGE_EVIDENCE_ROLE_TO_ASSUME` secret.

## Successful Run

The final workflow execution was
[run 34779633684](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/34779633684),
started from merged `main` commit
`43da086854dfa7cc622bc487a5ac3ecd47c27ae2` at `2026-09-13T20:04:46Z` and
completed successfully at `2026-09-13T20:08:18Z`.

Two earlier executions are not canonical evidence. Run `34778848422` stopped
at a hosted-runner Docker compatibility error before evidence generation. Run
`34779164078` completed signing, but its artifact layout retained an internal
runner path. Commit `43da086` flattened and structurally validated the bundles;
run `34779633684` is the first execution satisfying the complete contract.

Each matrix job successfully:

1. Exchanged the GitHub OIDC token for the dedicated pull-only AWS role.
2. Pulled the exact Linux/AMD64 ECR manifest by digest and verified its
   repository digest and platform.
3. Logged out of ECR and cleared temporary AWS credentials before analysis.
4. Generated SPDX 2.3 JSON with Syft 1.51.1.
5. Scanned fixed and unfixed high and critical findings with Trivy 0.74.0.
6. Enforced the zero-critical gate.
7. Created a GitHub-signed SBOM attestation, validated its Sigstore bundle, and
   uploaded the four evidence files.

## Subjects And Artifacts

The attestation subject is the runnable manifest, not the parent OCI index or
mutable tag. All four artifacts expire on `2026-12-12T20:04:48Z` under the
workflow's 90-day retention setting.

| Component | Job ID | Artifact ID | Runnable subject | Attestation |
| --- | ---: | ---: | --- | --- |
| Power simulator | `103784153633` | `10325115624` | `sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451` | [47199631](https://github.com/AnouarMohamed/grid-scada-security/attestations/47199631) |
| Modbus ingestor | `103784153697` | `10325385252` | `sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7` | [47199586](https://github.com/AnouarMohamed/grid-scada-security/attestations/47199586) |
| InfluxDB | `103784153622` | `10325355296` | `sha256:66e4f468821b9a47f9eb0808d2e87c70d6ddd92c741450e9d78eff70ae856d67` | [47199585](https://github.com/AnouarMohamed/grid-scada-security/attestations/47199585) |
| Grafana | `103784153579` | `10324981033` | `sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c` | [47199849](https://github.com/AnouarMohamed/grid-scada-security/attestations/47199849) |

| Component | Artifact name | Compressed bytes |
| --- | --- | ---: |
| Power simulator | `image-evidence-power-sim-34779633684` | 883573 |
| Modbus ingestor | `image-evidence-modbus-ingestor-34779633684` | 822724 |
| InfluxDB | `image-evidence-influxdb-34779633684` | 483656 |
| Grafana | `image-evidence-grafana-34779633684` | 543652 |

Every downloaded artifact had a flat component directory containing exactly:

- `<component>.attestation.json`
- `<component>.spdx.json`
- `<component>.summary.json`
- `<component>.trivy.json`

## Evidence Checksums

These SHA-256 values identify the downloaded files independently of the GitHub
artifact archive.

| Component | Attestation JSON | SPDX JSON |
| --- | --- | --- |
| Power simulator | `cf6104a0a72aac34f9d63b418f63996f32df6bd3db60376bb468df1dc22bae7b` | `ccb433bf2b3186cee279d1595a970da4a9d705dac33b645cd4b9c0e2b52540cf` |
| Modbus ingestor | `00ebd39853a0104da2021fad596111352825e9f563c8b9226bc7d4dc5f4f8228` | `172b6d6e3a2a9c3cf9065eeab91443e65223fd60d9054b503b536d59bd32876a` |
| InfluxDB | `f6418c718a856688953db162fa0bf001343e28742dea9addfdf582f7e35ffd99` | `1863fdd03e351d3fadce38fe3fa7f0326e1ff4f819b718e646bb7a58085d8984` |
| Grafana | `e79de1adf794acccc0bbebd5d4a5736677e1cc62cecf4f2c96e6fca1732aaf00` | `85f6d3cfdd94d9b968e5edee6331e57021faf75c0b9cde3a0ab711e9a74af883` |

| Component | Summary JSON | Trivy JSON |
| --- | --- | --- |
| Power simulator | `f0b4a89041c76c7455f42b83553c5fb1e9d7bc2e561ab8131c8ec43a8c52a21a` | `9307ed63ab7f575018175d71e33fe9da970ace75b445a8a7dd4aca90c1aaa41f` |
| Modbus ingestor | `7daa919f400c10f3503fc88ce4e3a84bdf08ca3076dc68b38313ab918cc1d463` | `c74026f2c2a453e95561daa1f1cfc009adf39aaae76498ce24961efab06f6f12` |
| InfluxDB | `efad25cc3a27e07b505e04d3a81681576fe8933e48a50b30298aea46441077bc` | `c1655246b267642fdce8f2ff98252435c167b8a137873b38e88a965afb003b16` |
| Grafana | `0dc12e30ed7d9b29586334031e6f5cb61eaedc99fa827afcc830ddbb2e7183aa` | `e9fa1d9b1ba4435f4203e7c178a35ae7b4dedf4035dcc5459cf8539a37d20b71` |

## Scan Result

| Image | Critical records | High records | Unique highs | Fixed unique highs | Unfixed unique highs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Power simulator | 0 | 46 | 10 | 2 | 8 |
| Modbus ingestor | 0 | 44 | 8 | 0 | 8 |
| InfluxDB | 0 | 70 | 41 | 40 | 1 |
| Grafana | 0 | 5 | 5 | 5 | 0 |

No ignore file or vulnerability exception was used. Zero critical findings
satisfied the automated evidence gate, but no high finding was silently
accepted or suppressed.

## Independent Verification

After download, all four bundles were checked for Sigstore bundle media type
`application/vnd.dev.sigstore.bundle.v0.3+json`, one DSSE signature, one
transparency-log entry, and a nonempty signing certificate.

`gh attestation verify` then succeeded independently for each digest-qualified
ECR subject while enforcing all of these constraints:

- Repository `AnouarMohamed/grid-scada-security`.
- Signing workflow
  `AnouarMohamed/grid-scada-security/.github/workflows/image-evidence.yml`.
- Predicate type `https://spdx.dev/Document/v2.3`.
- The corresponding downloaded Sigstore bundle.

The temporary ECR login used for independent subject resolution was removed
with `docker logout`, and the temporary AWS owner session was logged out. A
post-run check confirmed that all four ECR parent digests remained unchanged
and the ECS cluster still had zero services, zero running tasks, and zero
pending tasks.

## Decision And Next Gate

The evidence-control milestone is complete: exact runnable subjects have signed
SPDX attestations, retained scan reports, stable artifact identifiers, and an
independently verified GitHub signing identity.

Runtime remains blocked. The next engineering gate is either a fixed upstream
release or the documented CVE-by-CVE reachability and time-bounded risk
decision required by the
[container remediation record](2026-09-13-container-remediation.md).
