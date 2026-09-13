# AWS Foundation Deployment Role

This bootstrap creates a temporary human deployment path for the reviewed
Phase 1 Terraform foundation. It does not create network, compute, storage, or
runtime resources and has no direct AWS service charge.

The five baseline resources are:

- The account-wide Amazon ECS service-linked role, retained while ECS resources
  depend on it.
- An MFA-only role trusted exclusively by the named IAM operator.
- A Phase 1 deployment policy attached to that role.
- A workload-role permissions boundary retained for Terraform-managed roles.
- An exact `sts:AssumeRole` policy attached to the named operator.

An optional sixth managed policy grants the named operator temporary image-push
access to the four exact GridGuard ECR repositories. It is disabled by default
and must be removed immediately after the registry digests and scans are
verified.

The deployment policy deliberately omits NAT gateway, Elastic IP, VPC
endpoint, load balancer, EFS, Secrets Manager, ECS task definition, ECS
service, and image-push mutations. It can create only the reviewed foundation:
the VPC and subnet routing structure, security groups, VPC Flow Logs, scoped
CloudWatch log groups, four ECR repositories, one ECS cluster, and bounded IAM
workload roles. Its account-level ECR write is limited to configuring scanning
in the selected region; Terraform restricts that scan-on-push rule to
`gridguard-aws-sandbox/*`. It can manually start scans only for repositories
under that same prefix. Changing a runtime flag cannot bypass this policy gate.

Every IAM role created by this deployment role must carry the retained
`gridguard-aws-sandbox-workload-boundary`. The deployment role cannot remove or
replace that boundary, create managed policies, change users, or pass roles to
services other than ECS tasks and VPC Flow Logs.

## Validate Without Deployment

Use the non-root operator session. This performs identity and CloudFormation
syntax validation only:

```bash
AWS_PROFILE=default AWS_REGION=us-east-1 \
make aws-foundation-bootstrap-validate
```

## Owner-Executed Change Set

Create but do not execute a change set from the repository root:

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name gridguard-foundation-deployment \
  --template-file infra/cloudformation/bootstrap/foundation-deployment-role.yaml \
  --parameter-overrides \
    OperatorUserName="anouar-admin" \
    StateAccessPolicyArn="arn:aws:iam::227755136916:policy/gridguard/gridguard-aws-sandbox-terraform-state" \
    EnableOperatorImagePublish="false" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

The initial change set must contain exactly `EcsServiceLinkedRole`,
`WorkloadRoleBoundary`, `FoundationDeploymentPolicy`,
`FoundationDeploymentRole`, and `OperatorAssumeRolePolicy` as additions, with
no replacements or deletions. Execute only after inspecting those five
additions, then enable stack
termination protection and return to `anouar-admin`.

If the four IAM resources already exist from an earlier bootstrap revision,
update the stack with the current template. The update must add only
`EcsServiceLinkedRole`; it must not modify, replace, or delete another resource.
Wait for `UPDATE_COMPLETE`, then generate a fresh Terraform plan. A foundation
apply interrupted at ECS capacity-provider configuration should show exactly
one addition and no changes or deletions.

## Temporary Image Publication

Do not grant `AdministratorAccess` or an AWS-managed ECR power-user policy to
publish images. Update this stack with the current template and set
`EnableOperatorImagePublish` to `true`. The reviewed change set must add only
`OperatorEcrPublishPolicy`; it must not replace or delete another resource.

The policy allows registry authentication plus the six image push actions in
the AWS ECR push-permissions example. Its resources are the exact `power-sim`,
`modbus-ingestor`, `influxdb`, and `grafana` repositories in this account and
region. Repository immutability remains the independent control against tag
replacement. While this policy is enabled, the operator can publish new tags
to those four repositories, so enable it only for the publication session and
do not leave the console or workstation unattended.

After all four images are present, record their AWS-returned manifest digests
and confirm each configured ECR scan completes. Then update the same stack with
`EnableOperatorImagePublish` set back to `false`. The cleanup change set must
remove only `OperatorEcrPublishPolicy`. Execute it, wait for
`UPDATE_COMPLETE`, run `docker logout` for the account registry, and verify the
policy is no longer attached to the operator.

The ECR registry token can remain cached by Docker after publication. Logging
out removes that local credential; removing the IAM policy is the authoritative
AWS-side revocation of the temporary push permission.

## Local Role Profile

Configure a role profile after the stack reaches `CREATE_COMPLETE`. The MFA
value is entered only in the local terminal when AWS prompts for it; never
paste an MFA value into chat, Git, Terraform, or a shell-history command.

```ini
[profile gridguard-foundation]
role_arn = arn:aws:iam::227755136916:role/gridguard-aws-sandbox-foundation-deploy
source_profile = default
role_session_name = gridguard-foundation
region = us-east-1
```

The `default` source profile must be an active `aws login` session for
`anouar-admin`; that short-lived session already carries MFA context. The role
trust policy independently rejects a source session without MFA. Do not create
access keys or add an empty `mfa_serial` setting to this profile.

Terraform's embedded AWS SDK does not consume the AWS CLI `login_session`
setting directly. Bridge the assumed role through AWS CLI's standard
`credential_process` output; it returns short-lived credentials to the calling
process without persisting them:

```ini
[profile gridguard-terraform]
credential_process = aws configure export-credentials --profile gridguard-foundation --format process
region = us-east-1
```

Verify the assumed identity before planning or applying:

```bash
aws --profile gridguard-foundation sts get-caller-identity
```

The ARN must contain `assumed-role/gridguard-aws-sandbox-foundation-deploy/`.
Generate a fresh saved plan through the credential-process profile and compare
it with the reviewed 70-addition baseline:

```bash
AWS_PROFILE=gridguard-terraform \
terraform -chdir=infra/terraform/environments/aws-sandbox \
  plan -input=false -out=tfplan
```

Never apply an earlier operator-generated plan.

## After Phase 1

Do not broaden this role for runtime deployment. Create and review a separate
OIDC role and runtime policy after the foundation, images, secrets procedure,
private operator path, and cost estimate are ready. Boundary removal is an
owner-only teardown action because removing a permissions boundary can increase
a role's effective permissions.
