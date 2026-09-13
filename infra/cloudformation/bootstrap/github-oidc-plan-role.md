# GitHub OIDC Plan-Role Bootstrap

This bootstrap creates the smallest useful GitHub identity for the current
GridGuard stage. It creates exactly three retained IAM resources:

- The account-wide GitHub Actions OIDC provider.
- One customer-managed plan policy.
- One role that attaches that policy and uses the same policy as its
  permissions boundary.

The role trusts only
`repo:AnouarMohamed/grid-scada-security:environment:sandbox` with audience
`sts.amazonaws.com`. It can read the exact Terraform state object, create and
delete only that object's `.tflock`, use the exact state KMS key, and read the
AWS metadata needed by Terraform refresh and plan.

It cannot write or delete Terraform state, read secret values, pass a role,
assume another role, or mutate GridGuard infrastructure. The committed GitHub
workflow contains no apply input and no apply step. IAM and OIDC provider
resources have no hourly charge, but normal state-backend request charges can
still apply.

## Ownership And Preconditions

CloudFormation owns these resources. Keep Terraform's
`create_github_oidc_provider` and `enable_github_oidc_role` variables `false`;
do not import or recreate the same provider or role in Terraform.

Before using an owner session:

1. Merge the reviewed repository change through the protected branch.
2. Confirm the state-backend and foundation stacks are healthy.
3. Confirm no GitHub OIDC provider already exists in the account.
4. Run both validation layers with the non-root profile.

```bash
make cloudformation

AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
AWS_REGION="us-east-1" \
make aws-github-oidc-bootstrap-validate
```

The AWS validation calls `sts:GetCallerIdentity`,
`cloudformation:ValidateTemplate`, and IAM Access Analyzer's
`ValidatePolicy`. It creates no resource. Access Analyzer must return zero
findings for the resolved policy. The local validator also asserts the exact
trust claims, policy actions, state path, lock path, permissions boundary,
explicit denies, and three-resource limit.

Check the account-wide provider list before creating a change set:

```bash
AWS_PROFILE="REPLACE_OWNER_PROFILE" \
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[].Arn' \
  --output table
```

Stop if an ARN ending in `/token.actions.githubusercontent.com` already exists.
Do not create a duplicate. Review whether that provider has the exact
`sts.amazonaws.com` client ID and decide on ownership before proceeding.

## Owner-Created Change Set

Use an MFA-protected, browser-issued owner session only for this bootstrap. Do
not create a root access key and do not attach administrator access to the
normal operator. Set explicit profiles so the owner and operator sessions
cannot be confused.

Obtain the existing state boundary from CloudFormation:

```bash
export AWS_REGION="us-east-1"
export OWNER_PROFILE="REPLACE_OWNER_PROFILE"
export STATE_STACK="gridguard-state-backend"
export OIDC_STACK="gridguard-github-oidc-plan"

export STATE_BUCKET="$(aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation describe-stacks \
  --stack-name "$STATE_STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`StateBucketName`].OutputValue | [0]' \
  --output text)"
export STATE_KMS_KEY_ARN="$(aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation describe-stacks \
  --stack-name "$STATE_STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`StateEncryptionKeyArn`].OutputValue | [0]' \
  --output text)"

test -n "$STATE_BUCKET" && test "$STATE_BUCKET" != "None"
test -n "$STATE_KMS_KEY_ARN" && test "$STATE_KMS_KEY_ARN" != "None"
```

Create, but do not execute, the change set:

```bash
aws --profile "$OWNER_PROFILE" cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "$OIDC_STACK" \
  --template-file infra/cloudformation/bootstrap/github-oidc-plan-role.yaml \
  --parameter-overrides \
    GitHubRepository="AnouarMohamed/grid-scada-security" \
    GitHubEnvironment="sandbox" \
    RoleName="gridguard-aws-sandbox-github-plan" \
    PolicyName="gridguard-aws-sandbox-github-plan" \
    StateBucketName="$STATE_BUCKET" \
    StateKey="gridguard/aws-sandbox/terraform.tfstate" \
    StateKmsKeyArn="$STATE_KMS_KEY_ARN" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

Capture and inspect the exact change set produced by that command:

```bash
export CHANGE_SET_ID="$(aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation list-change-sets \
  --stack-name "$OIDC_STACK" \
  --query 'reverse(sort_by(Summaries[?Status==`CREATE_COMPLETE`], &CreationTime))[0].ChangeSetId' \
  --output text)"

test -n "$CHANGE_SET_ID" && test "$CHANGE_SET_ID" != "None"

aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation describe-change-set \
  --change-set-name "$CHANGE_SET_ID" \
  --query 'Changes[].ResourceChange.{Action:Action,LogicalId:LogicalResourceId,Type:ResourceType,Replacement:Replacement}' \
  --output table
```

The table must show exactly these three additions and no modification,
replacement, import, or deletion:

| Action | Logical ID | Type |
| --- | --- | --- |
| Add | `GitHubOidcProvider` | `AWS::IAM::OIDCProvider` |
| Add | `GitHubPlanPolicy` | `AWS::IAM::ManagedPolicy` |
| Add | `GitHubPlanRole` | `AWS::IAM::Role` |

Stop if the output differs. Execute only the reviewed change-set ID, wait for
completion, and immediately enable termination protection:

```bash
aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation execute-change-set \
  --change-set-name "$CHANGE_SET_ID"

aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation wait stack-create-complete \
  --stack-name "$OIDC_STACK"

aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation update-termination-protection \
  --stack-name "$OIDC_STACK" \
  --enable-termination-protection
```

## Post-Create Verification

Read the outputs and verify the stack, role boundary, and sole attachment:

```bash
aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation describe-stacks \
  --stack-name "$OIDC_STACK" \
  --query 'Stacks[0].{Status:StackStatus,TerminationProtection:EnableTerminationProtection,Outputs:Outputs}' \
  --output json

aws --profile "$OWNER_PROFILE" iam get-role \
  --role-name gridguard-aws-sandbox-github-plan \
  --query 'Role.{Arn:Arn,Boundary:PermissionsBoundary.PermissionsBoundaryArn,Trust:AssumeRolePolicyDocument}' \
  --output json

aws --profile "$OWNER_PROFILE" iam list-attached-role-policies \
  --role-name gridguard-aws-sandbox-github-plan \
  --output json
```

Expected status is `CREATE_COMPLETE`, termination protection is `true`, the
role boundary ends in `/gridguard/gridguard-aws-sandbox-github-plan`, and the
same single policy is attached. The trust document must contain only the exact
repository-environment subject and audience documented above.

End the privileged session before configuring GitHub:

```bash
aws logout --profile "$OWNER_PROFILE"
unset OWNER_PROFILE CHANGE_SET_ID
```

## GitHub Environment

Use a GitHub session authorized for this repository. Create or update the
`sandbox` environment so only protected branches can use it:

```bash
gh api --method PUT \
  repos/AnouarMohamed/grid-scada-security/environments/sandbox \
  --input - <<'JSON'
{
  "deployment_branch_policy": {
    "protected_branches": true,
    "custom_branch_policies": false
  }
}
JSON
```

Read the role and state outputs with the non-root profile, then set the exact
environment values:

```bash
export AWS_PROFILE="REPLACE_NON_ROOT_PROFILE"
export AWS_REGION="us-east-1"

ROLE_ARN="$(aws cloudformation describe-stacks \
  --stack-name gridguard-github-oidc-plan \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubPlanRoleArn`].OutputValue | [0]' \
  --output text)"
STATE_BUCKET="$(aws cloudformation describe-stacks \
  --stack-name gridguard-state-backend \
  --query 'Stacks[0].Outputs[?OutputKey==`StateBucketName`].OutputValue | [0]' \
  --output text)"
STATE_KMS_KEY_ARN="$(aws cloudformation describe-stacks \
  --stack-name gridguard-state-backend \
  --query 'Stacks[0].Outputs[?OutputKey==`StateEncryptionKeyArn`].OutputValue | [0]' \
  --output text)"
WORKLOAD_BOUNDARY_ARN="$(aws cloudformation describe-stacks \
  --stack-name gridguard-foundation-deployment \
  --query 'Stacks[0].Outputs[?OutputKey==`WorkloadRoleBoundaryArn`].OutputValue | [0]' \
  --output text)"

gh secret set AWS_ROLE_TO_ASSUME --env sandbox --body "$ROLE_ARN"
gh variable set AWS_REGION --env sandbox --body "$AWS_REGION"
gh variable set TF_STATE_BUCKET --env sandbox --body "$STATE_BUCKET"
gh variable set TF_STATE_KEY --env sandbox \
  --body "gridguard/aws-sandbox/terraform.tfstate"
gh variable set TF_STATE_KMS_KEY_ARN --env sandbox \
  --body "$STATE_KMS_KEY_ARN"

TF_VARS_JSON="$(jq -cn --arg boundary "$WORKLOAD_BOUNDARY_ARN" \
  '{availability_zones:["us-east-1a","us-east-1b"],workload_role_permissions_boundary_arn:$boundary}')"
gh variable set TF_VARS_JSON --env sandbox --body "$TF_VARS_JSON"
```

The non-default availability zones and workload-role boundary must match the
already-applied foundation. Do not put passwords, tokens, private keys, or
secret values in `TF_VARS_JSON`.

After the bootstrap change is merged to `main`, dispatch `AWS Sandbox Plan`
from GitHub Actions. Success means OIDC authentication, backend initialization,
state locking, refresh, and plan all complete. The expected plan result is **no
changes**. Stop on any proposed create, update, replace, or delete; do not add
permissions until the failed API action and its exact resource are understood.

## Recovery And Removal

Routine Terraform destroy does not own or remove this stack. CloudFormation
retains all three IAM resources if the stack is deleted or a resource is
replaced. This prevents an accidental stack deletion from silently breaking
the trust path, but final cleanup is intentionally manual.

For deliberate removal, first disable the workflow, remove the GitHub
environment secret, confirm no workflow run is active, disable termination
protection, delete the stack, and then separately inspect and delete the
retained role, policy, and provider. Delete the provider only after proving no
other repository or role uses it.

AWS documents the provider behavior in the official
[CloudFormation OIDC provider reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-iam-oidcprovider.html)
and [IAM CreateOpenIDConnectProvider API reference](https://docs.aws.amazon.com/IAM/latest/APIReference/API_CreateOpenIDConnectProvider.html).
The template omits `ThumbprintList`, allowing IAM to retrieve the current top
intermediate CA thumbprint instead of pinning stale certificate metadata in the
repository.
