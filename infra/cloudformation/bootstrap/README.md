# AWS State Backend Bootstrap

This directory also contains separately reviewed bootstraps for the
[foundation deployment role](foundation-deployment-role.md) and the
[GitHub plan-only OIDC role](github-oidc-plan-role.md). The
[GitHub image-evidence role](github-oidc-image-evidence-role.md) reuses that
OIDC provider but has its own ECR pull-only policy. Each bootstrap has an
independent change set, ownership boundary, and removal procedure.

The [temporary runtime deployment policy](runtime-deployment-policy.md)
attaches only while the reviewed runtime is being created, exercised, and
removed. Delete its one-resource stack after teardown.

This CloudFormation template breaks Terraform's backend bootstrap dependency
without keeping the backend itself in local Terraform state. It creates only:

- One S3 bucket retained on stack deletion or replacement.
- One bucket policy that denies non-TLS and pre-TLS-1.2 requests.
- One rotating customer-managed KMS key and its stable alias.
- One customer-managed IAM policy attached to the named non-root operator.

The bucket uses the dedicated KMS key, S3 Bucket Keys, versioning,
bucket-owner-enforced object ownership, and all four S3 Block Public Access
settings. The IAM policy can list only the configured state keys, can read and
write the state and lock objects, and can delete only the `.tflock` object. It
cannot delete Terraform state. No DynamoDB table, compute, or network resource
is created.

The customer-managed KMS key costs approximately `$1/month`, prorated hourly,
before request charges. S3 storage and requests remain usage-billed. KMS has a
20,000-request monthly free tier, but eligibility and pricing can change; check
the official [AWS KMS pricing](https://aws.amazon.com/kms/pricing/) before
deployment. Automatic key rotation is enabled. The first two completed key
rotations can each add another `$1/month`, so reassess retention before the
first annual rotation.

## Preconditions

Run the full account audit and continue only with zero failures and zero
unreviewed warnings:

```bash
AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
AWS_REGION="us-east-1" \
AWS_AUDIT_ALL_REGIONS="true" \
make aws-preflight
```

Choose a globally unique bucket name. A suitable form is
`gridguard-tfstate-REPLACE_ACCOUNT_ID-us-east-1`. The account ID is not a
secret. The template deliberately rejects periods for HTTPS compatibility and
rejects prefixes and suffixes reserved by S3. Do not bake credentials or
session tokens into any parameter or backend file.

The current read-only operator cannot deploy this stack. An account owner must
review and create it using a separately authorized administrative session.
Do not attach `AdministratorAccess` or create an access key for the operator.

## Read-Only Validation

The validation command rejects a root CLI session. It calls only
`sts:GetCallerIdentity` and `cloudformation:ValidateTemplate`; it does not
create a stack, change set, bucket, or IAM policy.

```bash
AWS_PROFILE="REPLACE_NON_ROOT_PROFILE" \
AWS_REGION="us-east-1" \
make aws-state-bootstrap-validate
```

Review the template and its `CAPABILITY_NAMED_IAM` declaration before any
deployment. Expected resource count: five additions, no replacements, and no
deletions: the bucket, bucket policy, KMS key, KMS alias, and IAM policy.

## Owner-Executed Change Set

From the repository root, create but do not execute a change set:

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name gridguard-state-backend \
  --template-file infra/cloudformation/bootstrap/state-backend.yaml \
  --parameter-overrides \
    StateBucketName="REPLACE_UNIQUE_BUCKET_NAME" \
    StateKey="gridguard/aws-sandbox/terraform.tfstate" \
    OperatorUserName="REPLACE_NON_ROOT_USER" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

Inspect the change set in CloudFormation. It must contain exactly
`StateBucket`, `StateBucketPolicy`, `StateEncryptionKey`,
`StateEncryptionKeyAlias`, and `StateAccessPolicy` as additions. Run the same
command without `--no-execute-changeset` only after that review.
Immediately enable stack termination protection after successful creation:

```bash
aws cloudformation update-termination-protection \
  --region us-east-1 \
  --stack-name gridguard-state-backend \
  --enable-termination-protection
```

Return to the non-root operator session after the owner-only bootstrap. Do not
continue if CloudFormation reports a replacement or deletion.

When a template is uploaded through the CloudFormation console, AWS creates or
reuses a regional `cf-templates-*` S3 bucket in the account. That helper bucket
is not a resource in this stack. After the stack reaches `CREATE_COMPLETE`,
confirm that CloudFormation can return both stored template stages before
removing the uploaded object and helper bucket if they are no longer needed:

```bash
aws cloudformation get-template \
  --region us-east-1 \
  --stack-name gridguard-state-backend \
  --template-stage Original \
  --query StagesAvailable
```

The expected result contains `Original` and `Processed`. Never confuse the
helper bucket with the retained `StateBucketName` output; the state bucket must
remain in place.

## Post-Create Verification

Confirm every bucket control before initializing Terraform:

```bash
aws s3api get-bucket-encryption --bucket "REPLACE_UNIQUE_BUCKET_NAME"
aws s3api get-bucket-versioning --bucket "REPLACE_UNIQUE_BUCKET_NAME"
aws s3api get-public-access-block --bucket "REPLACE_UNIQUE_BUCKET_NAME"
aws s3api get-bucket-ownership-controls --bucket "REPLACE_UNIQUE_BUCKET_NAME"
aws s3api get-bucket-policy-status --bucket "REPLACE_UNIQUE_BUCKET_NAME"
aws kms describe-key --key-id alias/gridguard/aws-sandbox/terraform-state
aws kms get-key-rotation-status \
  --key-id "REPLACE_STATE_ENCRYPTION_KEY_ARN"
```

Expected results are `aws:kms` with the stack's KMS key ARN, versioning
`Enabled`, all four public-access flags `true`, ownership
`BucketOwnerEnforced`, `IsPublic: false`, an enabled KMS key, and key rotation
enabled. Use the `StateEncryptionKeyArn` stack output for the rotation check;
that KMS operation does not accept an alias.

Copy the ignored backend example and replace the bucket name and KMS key ARN
with the CloudFormation outputs:

```bash
cd infra/terraform/environments/aws-sandbox
cp backend.tfbackend.example backend.tfbackend
terraform init -backend-config=backend.tfbackend
terraform validate
terraform test
```

The future GitHub OIDC deployment role needs equivalent permissions to the
same state and lock objects. Grant those permissions through its separately
reviewed deployment policy; do not make the bucket public or broaden this
operator policy to the whole bucket.

Before applying the Phase 1 foundation, create the MFA-gated
[foundation deployment role](foundation-deployment-role.md). Do not apply with
the root user or grant the operator `AdministratorAccess`.

## Recovery And Removal

Bucket versioning is the recovery mechanism for an overwritten or deleted
state object. Do not add automatic noncurrent-version expiration without a
separate recovery review. CloudFormation retains the bucket, bucket policy,
KMS key, KMS alias, and state-access policy if the stack is deleted or a
resource is replaced. That protects state from an accidental stack deletion,
but it also means final removal is a deliberate manual procedure.

Before any intentional cleanup, export and verify the latest state, inspect
all object versions, remove external policy attachments, disable stack
termination protection, and obtain explicit approval. Only schedule KMS key
deletion after all retained state has been safely removed. Never use a
recursive bucket deletion command as part of routine sandbox teardown.
