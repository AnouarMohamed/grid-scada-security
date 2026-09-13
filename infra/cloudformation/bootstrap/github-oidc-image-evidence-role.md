# GitHub Image-Evidence Role Bootstrap

This bootstrap creates a separate GitHub Actions identity for SBOM and
vulnerability evidence. It reuses the existing account-wide GitHub OIDC
provider and creates exactly two retained resources:

- One customer-managed read-only ECR policy.
- One OIDC role that attaches that policy and uses it as its permissions
  boundary.

The role trusts only
`repo:AnouarMohamed@235483559/grid-scada-security@1307773501:environment:sandbox`
with audience `sts.amazonaws.com`. It can authenticate to ECR and pull from
only the four GridGuard sandbox repositories. Explicit denies prevent ECR
mutation, secret retrieval, role passing, and role chaining.

The workflow logs out of ECR and clears its temporary AWS environment before
running the SBOM, scanner, attestation, and artifact actions. It pulls each
image by its recorded Linux/AMD64 manifest digest, generates SPDX JSON with
Syft, reports all fixed and unfixed high/critical findings with Trivy, blocks
any critical finding, and creates a GitHub-hosted signed SBOM attestation. It
does not push images or attestations to ECR.

## Preconditions

Merge the reviewed repository change first. Confirm the existing plan stack is
healthy and obtain its retained OIDC provider ARN:

```bash
export AWS_REGION="us-east-1"
export OWNER_PROFILE="REPLACE_OWNER_PROFILE"
export PLAN_STACK="gridguard-github-oidc-plan"

export OIDC_PROVIDER_ARN="$(aws --profile "$OWNER_PROFILE" \
  --region "$AWS_REGION" cloudformation describe-stacks \
  --stack-name "$PLAN_STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubOidcProviderArn`].OutputValue | [0]' \
  --output text)"

test -n "$OIDC_PROVIDER_ARN" && test "$OIDC_PROVIDER_ARN" != "None"
```

Do not create a second OIDC provider. Validate the template with the normal
non-root profile before using the owner session:

```bash
AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
AWS_REGION="us-east-1" \
make aws-image-evidence-bootstrap-validate
```

This performs only identity, CloudFormation validation, and IAM Access
Analyzer calls. It rejects root credentials and makes no resource changes.

## Owner-Reviewed Change Set

Create, but do not execute, the new stack change set:

```bash
export EVIDENCE_STACK="gridguard-github-image-evidence"

aws --profile "$OWNER_PROFILE" cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "$EVIDENCE_STACK" \
  --template-file infra/cloudformation/bootstrap/github-oidc-image-evidence-role.yaml \
  --parameter-overrides \
    GitHubOidcProviderArn="$OIDC_PROVIDER_ARN" \
    GitHubRepository="AnouarMohamed@235483559/grid-scada-security@1307773501" \
    GitHubEnvironment="sandbox" \
    RoleName="gridguard-aws-sandbox-github-image-evidence" \
    PolicyName="gridguard-aws-sandbox-github-image-evidence" \
    RepositoryPrefix="gridguard-aws-sandbox" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

Inspect the generated change set. Initial creation must contain exactly these
two additions, with no replacement, modification, import, or deletion:

| Action | Logical ID | Type |
| --- | --- | --- |
| Add | `GitHubImageEvidencePolicy` | `AWS::IAM::ManagedPolicy` |
| Add | `GitHubImageEvidenceRole` | `AWS::IAM::Role` |

Execute only the reviewed change-set ARN, wait for creation, and immediately
enable termination protection:

```bash
aws --profile "$OWNER_PROFILE" --region "$AWS_REGION" \
  cloudformation execute-change-set --change-set-name "REPLACE_CHANGE_SET_ARN"

aws --profile "$OWNER_PROFILE" --region "$AWS_REGION" \
  cloudformation wait stack-create-complete --stack-name "$EVIDENCE_STACK"

aws --profile "$OWNER_PROFILE" --region "$AWS_REGION" \
  cloudformation update-termination-protection \
  --stack-name "$EVIDENCE_STACK" --enable-termination-protection
```

Confirm the stack has two resources, termination protection is enabled, the
role has exactly one attached policy, and that policy is also its permissions
boundary. Then end the privileged session.

## GitHub Configuration And Run

Read the role output and store it as a second environment secret. Do not
replace the existing plan-role secret.

```bash
ROLE_ARN="$(aws --profile "$OWNER_PROFILE" --region "$AWS_REGION" \
  cloudformation describe-stacks --stack-name "$EVIDENCE_STACK" \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubImageEvidenceRoleArn`].OutputValue | [0]' \
  --output text)"

gh secret set AWS_IMAGE_EVIDENCE_ROLE_TO_ASSUME \
  --env sandbox --body "$ROLE_ARN"

aws logout --profile "$OWNER_PROFILE"
unset OWNER_PROFILE OIDC_PROVIDER_ARN ROLE_ARN
```

Run the workflow from merged `main` and watch it to completion:

```bash
gh workflow run image-evidence.yml --ref main

RUN_ID="$(gh run list --workflow image-evidence.yml \
  --branch main --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')"
test -n "$RUN_ID"
gh run watch "$RUN_ID" --exit-status
```

All four matrix jobs must pass. Each job retains its SPDX SBOM, complete Trivy
JSON report, compact finding summary, and signed attestation bundle for 90
days. GitHub also stores the attestation against the exact ECR repository name
and runnable digest.

## Verification And Limits

When already authenticated to ECR, verify a subject against the exact signer
workflow and SPDX predicate:

```bash
gh attestation verify \
  "oci://227755136916.dkr.ecr.us-east-1.amazonaws.com/gridguard-aws-sandbox/power-sim@sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451" \
  --repo AnouarMohamed/grid-scada-security \
  --signer-workflow AnouarMohamed/grid-scada-security/.github/workflows/image-evidence.yml \
  --predicate-type https://spdx.dev/Document/v2.3
```

The attestation is stored by GitHub, not in ECR, because this role has no
registry write permissions. The workflow proves which SBOM was generated for
each immutable runnable manifest; it does not approve the images for runtime.
Runtime remains blocked until the high-finding review is explicitly closed.

For removal, first disable stack termination protection. Deleting the stack
retains both IAM resources by design, so detach and delete them manually only
after the workflow and environment secret have been retired.
