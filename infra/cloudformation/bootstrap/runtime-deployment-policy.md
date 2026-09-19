# Temporary Runtime Deployment Policy

This one-resource bootstrap attaches temporary runtime lifecycle permissions to
the existing MFA-gated `gridguard-aws-sandbox-foundation-deploy` role. It does
not create runtime resources itself. Terraform remains responsible for the
reviewed ECS, EFS, internal ALB, private endpoint, Cloud Map, and secret
container resources.

EFS mount-target lifecycle includes its documented EC2 network-interface
dependencies. Enabling automatic EFS backups may create the AWS Backup
service-linked role, restricted by the `backup.amazonaws.com` service-name
condition.

Create and inspect the change set with the non-root `anouar-admin` session:

```bash
aws --profile default --region us-east-1 cloudformation deploy \
  --stack-name gridguard-runtime-deployment-policy \
  --template-file infra/cloudformation/bootstrap/runtime-deployment-policy.yaml \
  --parameter-overrides \
    DeploymentRoleName=gridguard-aws-sandbox-foundation-deploy \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

The change set must add exactly `RuntimeDeploymentPolicy`, with no replacement
or deletion. Execute it only for the runtime creation and teardown window.

After Terraform has returned desired counts to zero and removed the runtime
foundation, delete this CloudFormation stack. That detaches and removes the
temporary policy while preserving the foundation deployment role.
