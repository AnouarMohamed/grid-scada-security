# Container Vulnerability Remediation Record

This record explains the remediation performed after AWS ECR scanned the first
four GridGuard release images. It separates remediated operating-system
packages from findings compiled into third-party application binaries. Runtime
remains disabled; this record is not a risk-acceptance waiver.

## Trigger

ECR basic scanning completed successfully against the runnable Linux/AMD64
manifest inside each tagged OCI index. The initial images contained critical
findings in Debian Perl/OpenSSL or Alpine curl/OpenSSL packages. The local Trivy
gate had passed because it ignores findings without a vendor fix, while ECR's
severity totals include them.

The Debian tracker confirmed that the Bookworm Perl and OpenSSL versions were
still vulnerable while patched Trixie packages were available for
[CVE-2026-57433](https://security-tracker.debian.org/tracker/CVE-2026-57433),
[CVE-2026-75803](https://security-tracker.debian.org/tracker/CVE-2026-75803),
[CVE-2026-12087](https://security-tracker.debian.org/tracker/CVE-2026-12087),
and
[CVE-2026-13221](https://security-tracker.debian.org/tracker/CVE-2026-13221).
Live Alpine package indexes exposed newer curl, OpenSSL, SQLite, and supporting
packages for the pinned 3.23 and 3.24 base releases.

## Candidate Changes

| Image | New immutable tag | Remediation |
| --- | --- | --- |
| Power simulator | `0.1.1` | Digest-pinned Python 3.14 Trixie base; current distribution upgrades; `msgpack==1.2.1` |
| Modbus ingestor | `0.1.1` | Digest-pinned Python 3.12 Trixie base; current distribution upgrades |
| InfluxDB | `2.9.1-gridguard.1` | Retain pinned InfluxDB 2.9.1 Alpine base; upgrade installed Alpine packages |
| Grafana | `12.4.10-gridguard.1` | Retain pinned Grafana 12.4.10 base; upgrade installed Alpine packages |

Trivy 0.70.0 with its 2026-09-13 database reported zero critical findings,
including unfixed findings, for all four candidates. The actionable
`--ignore-unfixed` high-finding comparison was:

| Image | Fixed high findings | Disposition |
| --- | ---: | --- |
| Power simulator | 2 | Stale base-layer metadata; runtime packages verified below |
| Modbus ingestor | 0 | Clear |
| InfluxDB | 69 | Unresolved vendor-compiled Go dependencies |
| Grafana | 5 | Unresolved vendor-compiled Go dependencies |

Runtime inspection confirmed `msgpack 1.2.1` is installed and `setuptools` is
absent from the power simulator; the two high records for superseded
base-layer metadata are therefore not runtime packages.

## Unresolved Vendor Binaries

The patched InfluxDB candidate still reports fixed high findings compiled into
`influxd`, `influx`, and `dasel`; the patched Grafana candidate reports fixed
high findings compiled into the Grafana server. OS package upgrades cannot
replace dependencies statically linked into those Go executables. InfluxDB
2.9.1 remains the current supported v2 image needed by this Flux-based lab, and
testing Grafana 13.2.1 produced substantially more fixed high findings than
12.4.10 (176 instead of 5 with the same Trivy database).

These are not treated as resolved. InfluxDB will receive traffic from the
ingestor and Grafana, and Grafana will eventually receive operator traffic.
Before any desired count becomes nonzero, either:

1. Publish vendor releases rebuilt with fixed Go dependencies and repeat both
   local and ECR scans.
2. Produce a CVE-by-CVE reachability review, obtain explicit sandbox risk
   acceptance, and document compensating controls and the expiry date.

Rebuilding either upstream product from locally modified source is rejected for
now because it would create an unmaintained product fork and a larger software
supply-chain burden.

## Release Gate

The candidates may be stored in immutable ECR tags for evidence and future
rescan, but they must not be selected by a running ECS service yet. After
publication, record the ECR parent and runnable manifest digests, confirm scan
completion on the runnable manifests, and pin Terraform task definitions to
those digests. Runtime remains blocked until the vendor-binary decision above
is closed.
