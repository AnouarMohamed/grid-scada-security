# Conditional InfluxDB Runtime Risk Acceptance

- **Decision date:** 2026-09-19
- **Expiry:** 2026-10-19
- **Environment:** dedicated non-production `gridguard-aws-sandbox` in
  `us-east-1`
- **Decision:** conditionally accept the combined residual risk for one bounded
  lab exercise; this is not a production waiver.

Merging this record is the repository owner's approval of the conditions below.
The acceptance expires automatically, applies only to the exact subject, and
must not be copied to another environment or image.

## Exact Subject And Evidence

The only accepted subject is the Linux/AMD64 runnable ECR manifest:

```text
sha256:359adac56f03b03f1b7072cc2d34bd0a49262e920961ed74cb490ea6a21d8fb0
```

It is published as `influxdb:2.9.1-gridguard.2`; the OCI index digest is
`sha256:c9068f86b677578dcf51bf9fbc49dad025c3ebf62177471c5ed30b6aba49c8ee`.
The [signed evidence record](2026-09-14-signed-image-evidence.md) ties this
runnable manifest to its SPDX SBOM, complete Trivy report, GitHub attestation,
workflow run, and independent checksums.

A fresh Trivy 0.74.0 scan on 2026-09-19 used a database downloaded at
`2026-09-19T15:27:36Z`. It reproduced 0 Critical records, 59 High records, 36
unique High advisories, 36 with a published fix, and 0 without a published fix.
The report SHA-256 is
`75e1dd0b6e7e8367a8849a1f6bbbfbf644980a931cf0177804d91198e3224e84`.

Current `govulncheck` 1.8.0 binary symbol scans used the Go vulnerability
database updated at `2026-09-16T18:00:43Z`. They reported 12 results for
`dasel`, 21 for `influx`, and 50 for `influxd`, comprising 58 unique Go
advisory IDs. Forty-nine unique IDs had at least one symbol-call-level result;
the remainder were package- or module-level observations. A symbol result
means a vulnerable function is present in a compiled call path; it does not by
itself prove that the lab configuration exposes an exploitable network path.

The scanned binary and SARIF SHA-256 values are:

| Binary | Binary SHA-256 | SARIF SHA-256 |
| --- | --- | --- |
| `dasel` | `5006ee3a4239ab6a3edb1bf5c932874d814f7c276117ca677352697a4f547799` | `a82fd659dbff6e6d4c937a326c2f4de723ac1666d5318ea92a937122c842880f` |
| `influx` | `ee515aa3d5b6c35331fd34e9df720c7f3fe568a8bc4208f18c4052c6cf1f7563` | `cab0901bec997b80b5436ae9cefe37537e5a36a30b8592d8277fe24b88afc7e2` |
| `influxd` | `901858aa7d585a67e3708e97371f620d4dce0f9e9c1411a4f1a0a5726750a858` | `6e0b63f9a0de72acb93542275b2f8a0809005d38e1b499f08676413c5fd8df13` |

## Findings Accounted For

The 36 Trivy High advisories are grouped by affected surface; no finding is
suppressed or placed in an ignore file:

- HTML and templates: `CVE-2026-25681`, `CVE-2026-27136`,
  `CVE-2026-56858`.
- X.509, TLS, JOSE, and identity: `CVE-2026-27145`, `CVE-2026-34986`,
  `CVE-2026-56862`.
- OpenTelemetry: `CVE-2026-29181`, `CVE-2026-39883`.
- JSON, XML, ASN.1, MIME, URL, and Unicode parsing: `CVE-2026-32285`,
  `CVE-2026-33818`, `CVE-2026-42504`, `CVE-2026-56852`,
  `CVE-2026-56859`, `CVE-2026-56860`.
- DNS, HTTP, and HTTP/2: `CVE-2026-33811`, `CVE-2026-33814`,
  `CVE-2026-39820`, `CVE-2026-39821`, `CVE-2026-42499`,
  `CVE-2026-46600`, `CVE-2026-56853`.
- File/path handling: `CVE-2026-39822`, `CVE-2026-39836`.
- SSH agent, client, and known-hosts code: `CVE-2026-39828`,
  `CVE-2026-39829`, `CVE-2026-39830`, `CVE-2026-39831`,
  `CVE-2026-39832`, `CVE-2026-39835`, `CVE-2026-42508`,
  `CVE-2026-46595`, `CVE-2026-46597`, `CVE-2026-56854`.
- gRPC and xDS: `CVE-2026-84304`, `CVE-2026-84445`,
  `GHSA-hrxh-6v49-42gf`.

The broader Go advisory inventory is:

```text
GO-2024-2631, GO-2024-2947, GO-2026-4316, GO-2026-4514,
GO-2026-4918, GO-2026-4945, GO-2026-4970, GO-2026-4971,
GO-2026-4976, GO-2026-4977, GO-2026-4980, GO-2026-4981,
GO-2026-4982, GO-2026-4986, GO-2026-5005, GO-2026-5006,
GO-2026-5013, GO-2026-5014, GO-2026-5015, GO-2026-5016,
GO-2026-5017, GO-2026-5018, GO-2026-5019, GO-2026-5020,
GO-2026-5021, GO-2026-5023, GO-2026-5025, GO-2026-5026,
GO-2026-5027, GO-2026-5028, GO-2026-5029, GO-2026-5030,
GO-2026-5033, GO-2026-5037, GO-2026-5038, GO-2026-5039,
GO-2026-5426, GO-2026-5491, GO-2026-5506, GO-2026-5764,
GO-2026-5841, GO-2026-5856, GO-2026-5932, GO-2026-5942,
GO-2026-5970, GO-2026-5972, GO-2026-6061, GO-2026-6088,
GO-2026-6089, GO-2026-6090, GO-2026-6091, GO-2026-6218,
GO-2026-6303, GO-2026-6348, GO-2026-6354, GO-2026-6355,
GO-2026-6441, GO-2026-6443
```

## Exposure Analysis

The image is a required vendor database service and cannot be rebuilt from
source within this lab without changing the supported product boundary. The
official upstream image still embeds the affected vendor Go binaries. Replacing
the image tag alone therefore does not remove the findings.

The lab does not expose SSH, an SSH agent, mail/MIME ingestion, xDS, gRPC, JWE,
external OpenTelemetry input, or a public InfluxDB UI. `dasel` reads trusted
local startup configuration; the `influx` CLI performs local initialization
and health operations. The Windows-only path finding is inapplicable to the
Linux task. These facts materially reduce, but do not eliminate, reachability.

Residual HTTP, URL, Unicode, TLS, DNS, and parser denial-of-service paths in
`influxd` remain potentially reachable from trusted application peers. A
compromised Grafana or ingestor task could exercise that internal surface.
Impact is bounded to synthetic telemetry and a disposable non-production
environment, but service interruption and evidence loss remain possible.
Overall residual risk is **Moderate** for the bounded lab and **unacceptable**
for production or persistent operation.

## Mandatory Conditions

This acceptance is valid only while every condition is true:

1. The task uses the exact runnable digest above; no tag-only reference or
   substitute image is allowed.
2. A fresh scan less than 24 hours old shows zero Critical findings and no new
   materially reachable High finding.
3. The run uses only synthetic data and lab-only secrets in the dedicated
   sandbox account; production data, credentials, and integrations are absent.
4. `grafana_public=false`, NAT remains disabled, OT route tables have no
   default route, and InfluxDB accepts traffic only from the Grafana and
   Modbus-ingestor security groups.
5. SSH, mail, JWE/OIDC, xDS/gRPC, external collectors, plugins, and other
   unreviewed InfluxDB integrations remain disabled.
6. Runtime is actively supervised, lasts no more than eight hours, and uses one
   task per required service. It is returned to zero desired tasks immediately
   after evidence capture.
7. CloudWatch service logs, VPC flow logs, task/image metadata, target health,
   screenshots, detector outputs, and teardown state are captured under the
   [runtime evidence runbook](../13-aws-runtime-evidence.md).
8. Lab secret values are rotated or deleted after the exercise. Raw evidence is
   access-controlled and no secret values are committed.

## Stop Conditions

Do not start, or stop and isolate the runtime immediately, if any condition
changes; a Critical appears; the digest differs; a public route or listener is
observed; unexpected traffic, task behavior, or authentication failure occurs;
the eight-hour limit is reached; or evidence collection has an unexplained gap.

This acceptance becomes void at `2026-10-19T23:59:59Z`. Extending it requires a
new scan, fresh reachability review, new expiry, and a separately reviewed
record. A fixed upstream release must be preferred when available.
