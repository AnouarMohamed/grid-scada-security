# AWS Runtime Validation Record

This record documents the bounded GridGuard AWS runtime validation performed
in account `227755136916`, region `us-east-1`, on 2026-09-20. It contains no
credentials, secret values, Terraform state, raw logs, or private screenshots.
Those artifacts remain in ignored local evidence storage.

## Scope And Authorization

- Repository commit: `9c8fd50e700668540b00421d5c35ffe2e483faad`.
- Environment: dedicated non-production `gridguard-aws-sandbox` using only
  synthetic telemetry.
- Operator: non-root IAM user `anouar-admin`; Terraform applies used the
  MFA-gated `gridguard-aws-sandbox-foundation-deploy` role.
- The [conditional InfluxDB risk acceptance](2026-09-19-influxdb-runtime-risk-acceptance.md)
  applied only to runnable digest
  `sha256:359adac56f03b03f1b7072cc2d34bd0a49262e920961ed74cb490ea6a21d8fb0`.
- [Signed image evidence run 35456200149](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/35456200149)
  completed successfully for all four images before activation.
- [CI run 35507861217](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/35507861217)
  and [CodeQL run 35507861322](https://github.com/AnouarMohamed/grid-scada-security/actions/runs/35507861322)
  passed on the deployed commit.

The cloud exercise validated the baseline telemetry path and its controls. The
naive and stealthy attack/detection scenarios had already been exercised in
the local lab; they were not repeated against AWS because that would not add a
new control objective to this bounded deployment.

## Reviewed Changes

Every apply used a saved plan after resource-level inspection. SHA-256 values
identify the exact reviewed plan files; the files themselves were deleted
after use because Terraform plans can contain sensitive configuration.

| Change | Plan SHA-256 | Reviewed result |
| --- | --- | --- |
| Move the private Modbus path from privileged TCP/502 to TCP/1502 | `844f2d1a1f7c0c26d26565e4b01d054b7d3de7d987449f040c3cbbb07a15c249` | Two task-definition replacements, two service pointer updates, and two security-group rule updates |
| Activate the simulator and ingestor | `56d14ad34ae836b89f4e5bc52a9b3d45729a4a2905a27cadab5938c15b6262c2` | Only `power-sim` and `modbus-ingestor` desired counts changed from zero to one |
| Return all services to zero | `88d0110a64852a2eb9559515639eea6d00bd83c9bcc8497ab38a9916247530a9` | Four desired counts changed from one to zero; no resource creation or deletion |
| Remove the billable runtime foundation | `7fd45bc1fd840d99d2b6b50ffd5139e7ce9f7017abd98784a0f831c1bdd04b5c` | 38 runtime resources destroyed, one invariant updated, no additions or replacements |
| Post-removal convergence | `45392863059a957ffa1ebdf9e193340ac754e9736447d33325e73644a0219491` | `terraform plan -detailed-exitcode` returned zero with no changes |

An earlier removal plan with SHA-256
`3ff075d174b4ddcb3dfc55149e1cc40f6cc11d74a5508932ece04339617c2be2`
was not applied. The first attempt used the limited operator profile and was
denied before resource deletion; Terraform then rejected that saved plan as
stale. The plan was regenerated under the verified deployment-role session,
confirmed to have the identical 38-delete scope, and only the replacement
plan listed above was applied.

## Runtime Result

All four Fargate tasks reached `RUNNING` and `HEALTHY`. The task metadata tied
each running workload to its immutable ECR digest:

| Workload | Runnable digest |
| --- | --- |
| `power-sim` | `sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451` |
| `modbus-ingestor` | `sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7` |
| `influxdb` | `sha256:359adac56f03b03f1b7072cc2d34bd0a49262e920961ed74cb490ea6a21d8fb0` |
| `grafana` | `sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c` |

Cloud Map reported the simulator and ingestor healthy. The Grafana target at
private port 3000 was healthy behind the internal ALB. Logs showed the
simulator listening on `0.0.0.0:1502` and repeated successful ingestor cycles
with nine points written and zero detections. Short DNS lookup failures during
initial Cloud Map registration stopped once service discovery converged.

The network controls remained as reviewed: no NAT gateway, no public task IP,
no public Grafana listener, no default route from the isolated OT route table,
and only the ingestor security group could reach the simulator on TCP/1502.

## Evidence Inventory

| Evidence | SHA-256 | Result |
| --- | --- | --- |
| `20260920T113300Z-healthy.tar.gz` | `fccde24a2c33d6ba14d6efe9d3ea3360208150f038a4ddc1ff6d90c11a4268f3` | Healthy runtime API metadata and bounded logs; zero collection errors |
| `20260920T120000Z-shutdown.tar.gz` | `dc78552d8b13626f50e914f17ff881adc875941b134c8320bfffb71adaf8c3ff` | Four services at zero desired, running, and pending tasks; zero collection errors |
| `20260920-aws-console-evidence.tar.gz` | `f3ad1f56fb9a6cf69f837459beedcd2fb1ff1d7aba581b75f0ff6e2cf7c4c1a4` | Direct AWS Console screenshots plus per-file checksum inventory |

The healthy collector covered `2026-09-19T23:08:46Z` through
`2026-09-20T11:32:45Z` and explicitly recorded `secret_values_collected=false`.
The console set shows ECS service/task health, the VPC and routes, endpoints,
security groups, ECR, encrypted EFS, the internal ALB and target health, and
the simulator's single TCP/1502 ingress rule. Raw evidence contains account
identifiers, private addresses, and ARNs, so it remains ignored under `tmp/`
and must not be published without redaction.

## Deviation

The evidence window spans more than the acceptance's eight-hour maximum. The
stateful services remained active during a user pause, so this run did not
satisfy that time-limit condition. This is recorded as a process deviation,
not represented as compliant. No public exposure or unexpected workload
behavior was observed, and the runtime was stopped and removed when work
resumed. A future accepted run must use an automatic deadline alarm or
scheduled scale-to-zero control instead of relying only on an operator timer.

## Teardown And Retained Foundation

The four services first reached zero desired, running, and pending tasks. The
subsequent reviewed apply removed the services, task definitions, EFS file
systems and access points, internal ALB, Cloud Map namespace and services,
runtime secret containers, and all five VPC endpoints. The two secrets entered
scheduled deletion at 2026-09-20 12:10 UTC. Local plaintext secret files and
all saved Terraform plans were deleted after verification.

Independent AWS queries then returned no ECS services or tasks, no GridGuard
load balancer, no GridGuard EFS file systems, and no endpoints in the VPC. The
retained foundation consists of the VPC, six subnets, isolated route model,
flow logs, seven security groups, an active empty ECS cluster, bounded IAM
roles, and four immutable AES-256-encrypted ECR repositories. Terraform's
post-removal plan reported no drift.

The account owner deleted the one-resource
`gridguard-runtime-deployment-policy` CloudFormation stack after teardown.
Independent checks returned `does not exist` for the stack and `NoSuchEntity`
for its `gridguard-aws-sandbox-runtime-deploy` managed policy. The limited
operator and deployment roles intentionally could not perform this cleanup.

## Outcome

The private telemetry path, container health, service discovery, storage,
observability target, least-privilege network path, immutable image selection,
evidence capture, scale-to-zero procedure, and full runtime teardown were all
validated. The reusable default-off foundation remains ready for a future
reviewed exercise. The eight-hour supervision deviation is the only recorded
acceptance exception and requires the preventive control above before another
bounded run.
