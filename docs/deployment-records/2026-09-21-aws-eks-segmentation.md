# AWS EKS Segmentation Validation Record

This record documents the completed GridGuard Kubernetes validation in AWS
account `227755136916`, region `us-east-1`. The final evidence collection began
at `2026-09-21T20:39:03Z` against repository commit
`e45e2dd7c7e3b3b4f4ef42a29cb29355bb747f2f`.

## Scope And Safety Boundary

- One real Amazon EKS cluster, `gridguard-aws-eks-lab`, hosted the lab.
- The environment used synthetic IEEE 13-node approximation telemetry only.
- Two On-Demand `t3.small` workers ran in private subnets across
  `us-east-1a` and `us-east-1b`; neither instance had a public IP address.
- No workload used a public Kubernetes Service, load balancer, NAT gateway, or
  Internet Gateway egress route.
- The EKS API retained private access and temporary public access restricted to
  the operator address `196.117.93.106/32`.
- The final evidence set contains no credential or Kubernetes Secret values.

The EKS cluster and its supporting endpoints remain live and billable at the
end of this record. Teardown is deliberately not claimed. It must follow final
report review using the reviewed destroy procedure in the
[EKS Terraform runbook](../../infra/terraform/environments/aws-eks-lab/README.md).

## Verified Infrastructure

| Control | Observed result |
| --- | --- |
| EKS control plane | `ACTIVE`, Kubernetes `1.36` |
| Control-plane logging | API, audit, and authenticator logs enabled |
| Managed node group | `ACTIVE`, empty health issue list |
| Worker capacity | Two On-Demand `t3.small` nodes, min/max/desired all `2` |
| Worker placement | One private worker in `us-east-1a`; one in `us-east-1b` |
| Private AWS access | EKS, EC2, ECR API, ECR Docker, CloudWatch Logs, and STS interface endpoints with private DNS; S3 gateway endpoint |
| Workload exposure | Four `ClusterIP` Services; zero public Services or load balancers |
| Terraform state | Final detailed-exit plan returned `0` and `No changes` |

The three workload namespaces were `gridguard-ot`, `gridguard-ingestion`, and
`gridguard-observability`. Each had default-deny ingress and egress. Explicit
policies admitted only DNS, ingestor-to-simulator TCP/1502,
ingestor-to-InfluxDB TCP/8086, Grafana-to-InfluxDB TCP/8086, and the labeled
operator path to Grafana TCP/3000.

The managed Amazon VPC CNI reported strict startup enforcement through
`NETWORK_POLICY_ENFORCING_MODE=strict`; its `aws-eks-nodeagent` ran with
`--enable-network-policy=true`. CoreDNS received a separate minimum policy for
node health probes, the Kubernetes API Service VIP `172.20.0.1/32` on TCP/443,
and the VPC resolver `10.40.0.2/32` on UDP/TCP 53.

## End-To-End Result

All four deployments rolled out successfully: power simulator, Modbus
ingestor, InfluxDB, and Grafana. The automated smoke test proved every intended
allow and deny path, then exercised the real Modbus-to-InfluxDB application
flow. It observed `4,041` stored value rows in the archived run, required
fields `attack_flag`, `quality`, and `value`, source `modbus_tcp`, all six
required tags, all 15 Grafana panels, and all three alert rules.

| Probe | Result |
| --- | --- |
| Ingestor to simulator | Allowed |
| Untrusted pod to simulator | Denied |
| Grafana to simulator | Denied |
| Ingestor to InfluxDB | Allowed |
| Grafana to InfluxDB | Allowed |
| Simulator to InfluxDB | Denied |
| Untrusted pod to InfluxDB | Denied |
| Real Modbus ingestion | Passed |
| InfluxDB and Grafana health | Passed |

## Attack And Dashboard Evidence

The same live cluster replayed all three deterministic scenarios. Queries used
fresh, scenario-specific windows rather than mixing old series.

| Scenario | Fresh points | Detection observation | UI result |
| --- | ---: | --- | --- |
| `baseline-modbus` | 540 | Zero detections; `attack_flag=0` | Grafana clear; normal voltage range |
| `naive-bad-value` | 135 | Ten detections per cycle; `attack_flag=1` | Grafana flagged; voltage minimum `0.88 pu` |
| `stealthy-fdia` | 135 | Nine ground-truth flag detections per cycle; `attack_flag=1` | Grafana flagged; coordinated deviations visible |

The stealthy replay remains intentionally in-envelope. Its ground-truth flag
is forwarded, but the voltage-envelope detector does not independently detect
the manipulation. This is a demonstrated limitation, not a claim of advanced
state-estimation detection.

The six sanitized application figures are versioned under
`docs/report-assets/`. Their SHA-256 values are:

| Figure | SHA-256 |
| --- | --- |
| `grafana-baseline-modbus.png` | `5c9d1a3cad388b004a44f09a510e360588bdd4ff4b87704e36ec9b5d0132a14b` |
| `grafana-naive-bad-value.png` | `1510f2605a815b8561e19b2beb5abe2268354997dd15aafe45e202ab60e17c86` |
| `grafana-stealthy-fdia.png` | `3fbcb0a3d2195425bbf1d5af1e5a791fb01838dc10b2130759b4981e67f6fdf8` |
| `influxdb-baseline-modbus.png` | `3aee5cdb7dd826d3b894feb7c02a44f5e6164b841b3aad3269291c344c035750` |
| `influxdb-naive-bad-value.png` | `521d23a98ac44a7ac234b9df2126d4d3cc0c46cdb6c1af0c55c943888533dbb6` |
| `influxdb-stealthy-fdia.png` | `29a02ffd5bce4e443438caece2288601fc09e704f5639907dcf7bc531d7db420` |

Eight authenticated AWS Console figures are versioned beside them:

| Figure | SHA-256 |
| --- | --- |
| `aws-eks-cluster-overview.png` | `c73eaa8f511d8aae3ef386eeb6d909718f88aecdebc24cc9924dfe8ce6f5ba61` |
| `aws-eks-node-group.png` | `88eeb99c009dfde328cfa3a2ea487adec2341d0d0415d64afd0130373100ce75` |
| `aws-eks-vpc-cni-addon.png` | `cdeff061b6d9f409e15e46c7db1e9d2b561fd1e74458a615611873a9ccebc57d` |
| `aws-eks-control-plane-logging.png` | `a0afef5e1908e0fd27e849702f5a43461a0651383c0ac70830551b95912d2286` |
| `aws-ec2-private-workers.png` | `99820cb070cc3a3b987aed709e0ceeabd12cd1d9cdb4796bd31d3f7ae17a4f9f` |
| `aws-vpc-private-subnets.png` | `86b769f59842b754bc954e55f845e3410033a4742f073d55859e28d97f74c63b` |
| `aws-vpc-endpoints.png` | `84b1dcfb8680e59c7e7d52da6988d805b64a6340c03f6d9a2e5bfe6a68d5c665` |
| `aws-vpc-security-groups.png` | `d9d1cdf072a40cc91cfeab5f7673b0bce87cf5934f10ab9a669f8f904793fb86` |

## Evidence Integrity

The ignored raw evidence directory is `tmp/eks-runtime-evidence/20260921T203903Z`.
Its archive is `tmp/eks-runtime-evidence/20260921T203903Z.tar.gz`, with SHA-256:

```text
9efc81670cb9aa38d7a13dd68489dd8d5110cff1db3f169dbaaa4877fbe3c9f2
```

The archive contains 20 individually checksummed items: AWS cluster, node
group, worker, add-on, and endpoint metadata; Kubernetes inventories and policy
endpoints; the six UI captures; the successful segmentation smoke transcript;
the zero-drift Terraform transcript; and capture time, Git commit, and Git
status metadata. `sha256sum -c` verified the manifest, and the captured Git
status was empty.

Raw AWS and Kubernetes metadata remain ignored because they contain account
identifiers, ARNs, instance identifiers, and private addresses. The sanitized
record and report figures contain no authentication material.

The supplementary console archive
`tmp/eks-aws-console-20260922.tar.gz` has SHA-256
`8b933e8457218ab88733bab52ae6a3ff574174fb28b6a468a07a135ed385743f`.
Its verified manifest covers eight authenticated AWS Console pages and the
capture time. It was captured from an existing browser session with cookies
handled in memory only; no cookie value, browser profile, or login material is
stored in the archive or repository.

The rendered 12-page `docs/GridGuard-Technical-Report.pdf` has SHA-256
`6c238bfd070dbe30903ca42fac7c6f2cf5569ca5d7ad4c32c7733245cef2eb73`.
Its text extraction reaches the final teardown statement, and page raster
inspection confirmed that all architecture, AWS Console, Grafana, and InfluxDB
figures are centered, readable, and free of clipping or overlap.

## Remediations During Execution

1. The initial node group could not pull EKS system images because its
   permissions boundary allowed only project ECR repositories. The boundary
   was narrowed to read-only layer actions on the exact five AWS-owned EKS
   repositories used by the live nodes. No wildcard ECR write access was
   added.
2. Strict VPC CNI startup isolation also isolated CoreDNS. A dedicated policy
   added only node health probes, the API Service VIP, and VPC DNS resolver
   traffic.
3. Kubernetes manifests now pin the numeric runtime UID and GID for all four
   workloads, including `999:999` for the two GridGuard images.
4. The smoke test now checks the current `aws-eks-nodeagent` name and stores
   long log output before matching it, preventing a `pipefail`/SIGPIPE false
   negative.

## Outcome

The single-cluster cloud Kubernetes requirement is satisfied end to end. The
lab demonstrates private worker placement, strict namespace isolation,
positive and negative network enforcement, real Modbus ingestion, persistent
time-series data, Grafana visualization, two attack replays, alert evidence,
reproducible Terraform, and checksummed proof. The remaining operational step
is controlled teardown after the final report has been reviewed.
