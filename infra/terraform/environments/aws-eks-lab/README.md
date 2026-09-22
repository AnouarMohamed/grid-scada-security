# AWS EKS Segmentation Lab

This Terraform root creates one short-lived Amazon EKS cluster inside the
retained GridGuard VPC. It exists to prove Kubernetes namespace segmentation,
network-policy enforcement, and the real Modbus-to-InfluxDB-to-Grafana path in
AWS. It does not replace or import the separately validated ECS foundation.

## Architecture And Cost Boundary

The cluster uses EKS Kubernetes 1.36 in standard support and two On-Demand
`t3.small` workers across the existing private cloud subnets. This type is
Free-Tier eligible for the lab account and provides more pod-address and memory
capacity than the eligible micro types. Six interface
endpoints plus one S3 gateway endpoint let private workers reach only the AWS
services required for bootstrap, ECR pulls, CNI operation, STS, and logs. No
NAT gateway, public node address, Kubernetes `LoadBalancer`, or `NodePort` is
created. The Kubernetes API supports private access and restricts its public
endpoint to the current operator IPv4 `/32`.

Amazon EKS standard-support control planes cost `$0.10` per cluster-hour.
Workers, endpoint ENIs, logs, and data transfer are additional. Keep the whole
exercise below eight hours, monitor the existing budget, and destroy this
root immediately after evidence capture. Verify current prices on the
[official EKS pricing page](https://aws.amazon.com/eks/pricing/).

## Kubernetes Trust Zones

| Namespace | Workloads | Allowed application paths |
| --- | --- | --- |
| `gridguard-ot` | Power simulator | Ingress from the labeled ingestor on TCP/1502 |
| `gridguard-ingestion` | Modbus ingestor | Egress to the simulator on TCP/1502, InfluxDB on TCP/8086, and cluster DNS |
| `gridguard-observability` | InfluxDB and Grafana | InfluxDB ingress from the ingestor and Grafana; Grafana egress to InfluxDB and DNS |

Every namespace starts with default-deny ingress and egress. The Amazon VPC
CNI add-on must run its network-policy agent with policy support enabled and
`NETWORK_POLICY_ENFORCING_MODE=strict`. The smoke test fails unless both facts
are visible in the live `aws-node` DaemonSet and the positive and negative
connection probes behave as specified.

Strict mode also isolates new system pods during bootstrap. The AWS overlay
therefore gives CoreDNS only the runtime paths it needs: health probes from the
two private worker CIDRs, Kubernetes API synchronization on TCP/443 to the
cluster service VIP at `172.20.0.1/32`, and UDP/TCP DNS to the VPC resolver at
`10.40.0.2/32`. CI pins this policy's selector, CIDRs, and ports so it cannot
broaden silently.

The four application images are pulled from the existing private ECR
repositories by exact runnable digest. Workloads run as non-root, drop all
Linux capabilities, disable privilege escalation and service-account token
mounting, use read-only root filesystems and `RuntimeDefault` seccomp, and
define health probes plus resource requests and limits. Services remain
`ClusterIP` only. Bounded `emptyDir` mounts provide only the runtime paths that
InfluxDB and Grafana must write.

InfluxDB and Grafana use bounded `emptyDir` volumes because this cluster is a
short-lived evidence environment. The previous ECS exercise separately proved
encrypted persistent storage. Do not treat this EKS root as persistent or
production-ready storage.

The EKS role boundary was reconciled on 2026-09-21 against the current AWS
managed-policy versions: `AmazonEKSClusterPolicy` v10,
`AmazonEKSWorkerNodePolicy` v3, `AmazonEKS_CNI_Policy` v6, and
`AmazonEC2ContainerRegistryPullOnly` v1. In addition to the GridGuard image
repositories, it permits read-only pulls from the five exact AWS-owned EKS
system repositories used by VPC CNI, its network-policy agent, kube-proxy, and
CoreDNS. The boundary deliberately excludes wildcard repository access,
load-balancer, dynamic-volume, and upstream-import actions that this lab does
not use.

## Reviewed Scanner Exceptions

Two resource-scoped Trivy ignores are attached directly to the EKS cluster:

- `AVD-AWS-0039`: EKS 1.36 receives envelope encryption for all Kubernetes API
  data by default through an AWS-owned KMS key. AWS states that clusters on
  Kubernetes 1.28 or later require no configuration or additional permission.
  Adding a customer-managed key would duplicate the control and add KMS cost.
- `AVD-AWS-0040`: the public API endpoint is needed for this short-lived lab's
  local `kubectl` evidence workflow. It is not open to the internet: Terraform
  requires one operator IPv4 `/32`, enables the private endpoint, and rejects
  `0.0.0.0/0`. AWS documents this public-plus-private, single-CIDR pattern.

These exceptions do not weaken the repository-wide Trivy severity gate and
apply only to `aws_eks_cluster.this`. Confirm the encryption state in the EKS
console during evidence capture. References: [EKS default envelope
encryption](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
and [EKS endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html).

## Owner-Reviewed Bootstraps

Two CloudFormation change sets precede Terraform:

1. Update `gridguard-state-backend` from
   [`state-backend.yaml`](../../../cloudformation/bootstrap/state-backend.yaml).
   The change set must modify only `StateAccessPolicy` in place to authorize
   `gridguard/aws-eks-lab/terraform.tfstate` and its lock object.
2. Create `gridguard-eks-lab-deployment-policy` from
   [`eks-lab-deployment-policy.yaml`](../../../cloudformation/bootstrap/eks-lab-deployment-policy.yaml).
   It must add exactly `EksLabDeploymentPolicy` and `EksLabRoleBoundary`.

An account owner executes the reviewed change sets. Return to the non-root,
MFA-gated deployment role for every Terraform operation. Never apply this root
as the AWS account root user.

## Initialize And Plan

Copy the ignored backend and variable files:

```bash
cp backend.tfbackend.example backend.tfbackend
cp terraform.tfvars.example terraform.tfvars
```

Use the existing state bucket and KMS key, but keep the EKS key exactly
`gridguard/aws-eks-lab/terraform.tfstate`. Fill the retained VPC, two
cloud-private subnet IDs and CIDRs, cloud route table, current public `/32`,
deployment-role ARN, and EKS boundary output. Then initialize and validate:

```bash
AWS_PROFILE=gridguard-terraform AWS_REGION=us-east-1 \
terraform init -backend-config=backend.tfbackend
terraform validate
terraform test
```

Save a plan and review every action:

```bash
AWS_PROFILE=gridguard-terraform AWS_REGION=us-east-1 \
terraform plan -out=eks-create.tfplan
terraform show -json eks-create.tfplan > ../../../../tmp/eks-create-plan.json
sha256sum eks-create.tfplan
```

Expected cost-bearing resources are one EKS control plane, two EC2 workers,
12 interface endpoint ENIs, and control-plane logs. Stop if the plan contains
a NAT gateway, load balancer, public IP, public service, unbounded API CIDR,
resource outside the `gridguard-aws-eks-lab` namespace, or any change to the
retained ECS foundation.

## Deploy And Prove Segmentation

Apply only the reviewed saved plan, configure `kubectl`, and deploy the app:

```bash
AWS_PROFILE=gridguard-terraform AWS_REGION=us-east-1 \
terraform apply eks-create.tfplan
aws eks update-kubeconfig \
  --profile gridguard-terraform \
  --region us-east-1 \
  --name gridguard-aws-eks-lab \
  --alias gridguard-aws-eks-lab
make eks-app-deploy
make eks-segmentation-smoke
```

`eks-app-deploy` reads credentials from ignored `.env`, creates Kubernetes
Secrets without printing their values, provisions the existing Grafana
dashboard and alerts as ConfigMaps, and applies the digest-pinned AWS overlay.
The smoke test proves the following paths:

- allow labeled ingestor to simulator TCP/1502;
- allow labeled ingestor and Grafana to InfluxDB TCP/8086;
- deny an unlabeled ingestion pod from simulator TCP/1502;
- deny Grafana from simulator TCP/1502;
- deny the simulator and an untrusted observability pod from InfluxDB;
- observe `modbus_ingest_ok` from the real ingestor;
- query real `grid_telemetry` rows from InfluxDB; and
- execute every provisioned Grafana panel and all three alert rules.

Use `make eks-forward` for temporary localhost-only UI access. Capture the
baseline dashboard, InfluxDB Data Explorer query, naive attack, stealthy
attack, namespace/policy inventory, and denied probes. Never capture Secrets,
tokens, browser storage, Terraform state, or kubeconfig credentials.

## Teardown

After evidence capture, remove the in-cluster application Secrets and
namespaces, then destroy the EKS root from a saved, reviewed plan:

```bash
make eks-app-remove
AWS_PROFILE=gridguard-terraform AWS_REGION=us-east-1 \
terraform plan -destroy -out=eks-destroy.tfplan
sha256sum eks-destroy.tfplan
AWS_PROFILE=gridguard-terraform AWS_REGION=us-east-1 \
terraform apply eks-destroy.tfplan
```

Independently confirm there is no EKS cluster, node group, EKS endpoint, EC2
worker, or EKS-specific VPC endpoint. A normal plan must then report no
changes. Finally, an account owner deletes
`gridguard-eks-lab-deployment-policy`; verify both managed policies are gone.
The encrypted EKS state object and its versions remain for audit and recovery.
