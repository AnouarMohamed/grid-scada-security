# AWS Foundation Deployment Record

This sanitized record captures the first GridGuard AWS sandbox foundation
deployment. It intentionally omits the account number, resource identifiers,
user identity, email address, and local credential configuration.

## Change Identity

| Field | Recorded value |
| --- | --- |
| Deployment date | 2026-09-12 |
| Region | `us-east-1` |
| Repository revision applied | `5900ea0` |
| Terraform root | `infra/terraform/environments/aws-sandbox` |
| Runtime enabled | `false` |
| VPC endpoints enabled | `false` |
| NAT gateway enabled | `false` |
| Public Grafana enabled | `false` |

## Verified Evidence

| Control | Result |
| --- | --- |
| State-backend CloudFormation stack | `CREATE_COMPLETE`; termination protection enabled |
| Foundation-role CloudFormation stack | `UPDATE_COMPLETE`; termination protection enabled |
| Terraform post-apply plan | `No changes`; detailed exit code `0` |
| Terraform state | 74 addresses: 70 managed objects and 4 data sources |
| ECS cluster | `ACTIVE`; Container Insights enabled |
| Capacity providers | `FARGATE`, `FARGATE_SPOT`; `FARGATE` default |
| ECS runtime | 0 running tasks, 0 pending tasks, 0 active services |
| Availability zones | `us-east-1a`, `us-east-1b` |
| Subnets | 2 public-ingress, 2 cloud-core, 2 OT-sim; automatic public IP disabled on all |
| Cloud-core routes | VPC-local route only |
| OT-sim routes | VPC-local route only |
| Public-ingress routes | VPC-local route plus Internet Gateway default route |
| VPC flow logs | `ACTIVE`; all traffic; CloudWatch Logs; no delivery error |
| Application security groups | No `0.0.0.0/0` or IPv6 ingress; explicit ports and security-group references only |
| Workload IAM roles | Required permissions boundary attached |
| ECR | 4 repositories; immutable tags, scan-on-push, AES-256 encryption |
| Application logs | 5 log groups; 14-day retention |
| Cost budget | `$20` monthly cost budget present; actual spend reported as `$0` at verification time |
| Cost anomaly detection | Service monitor present; daily email subscription confirmed |

The VPC default security group retains the AWS-created self-reference and
default egress rule, but no GridGuard resource is configured to use it.

## Deliberately Absent

The administrator inventory confirmed that no NAT gateway, VPC endpoint,
Elastic IP, application load balancer, EFS file system, runtime secret, ECS
task definition, or ECS service had been created. The ECR repositories were
empty at the time of this foundation record.

## Recovery Note

The initial Terraform apply created the foundation resources but could not set
the cluster capacity providers because the account did not yet contain the ECS
service-linked role. The reviewed CloudFormation stack update added only
`AWS::IAM::ServiceLinkedRole` for `ecs.amazonaws.com`. A new Terraform plan
then contained exactly one create, `aws_ecs_cluster_capacity_providers.this`,
and the follow-up apply completed. The final post-apply plan reported no drift.

## Remaining Gates

- Publish the four release images only after the documented Trivy report and
  fixed-critical gate pass; use the temporary exact-repository publisher
  policy and record the resulting ECR manifest digests.
- Remove the temporary CloudFormation template bucket after the stack update
  artifact is no longer needed. Never remove the Terraform state bucket.
- Configure and review GitHub OIDC, the runtime deployment policy, and the
  `sandbox` environment approval before workflow-based deployment.
- Decide and test the private operator path to the internal Grafana ALB.
- Enable runtime and endpoints with desired counts still zero, populate secret
  values out of band, and start stateful services before data-plane services.

## Revalidation

Revalidate with a saved Terraform plan and live AWS API reads before every
runtime window. Stop if the plan includes an unexpected replacement or delete,
if an isolated route table gains a default route, or if a workload receives a
public IP.
