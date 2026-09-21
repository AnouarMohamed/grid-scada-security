# Temporary EKS Lab Deployment Policy

This bootstrap attaches temporary, name-scoped EKS lifecycle permissions to
the existing MFA-gated `gridguard-aws-sandbox-foundation-deploy` role. It also
creates the permissions boundary required by the two short-lived EKS IAM
roles. It creates no cluster, node, endpoint, workload, or secret.

Create but do not execute the change set with the non-root operator session:

```bash
aws --profile default --region us-east-1 cloudformation deploy \
  --stack-name gridguard-eks-lab-deployment-policy \
  --template-file infra/cloudformation/bootstrap/eks-lab-deployment-policy.yaml \
  --parameter-overrides \
    DeploymentRoleName=gridguard-aws-sandbox-foundation-deploy \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

The reviewed change set must add exactly `EksLabDeploymentPolicy` and
`EksLabRoleBoundary`, with no replacement or deletion. An account owner
executes it only for the EKS creation, evidence, and teardown window.

Use the `EksLabRoleBoundaryArn` output in the ignored EKS Terraform variables.
Terraform then creates only the exact cluster and node roles named in this
policy, and both roles must carry that boundary.

The boundary was reconciled on 2026-09-20 against `AmazonEKSClusterPolicy` v10,
`AmazonEKSWorkerNodePolicy` v3, `AmazonEKS_CNI_Policy` v6, and
`AmazonEC2ContainerRegistryPullOnly` v1. It permits the documented minimum
cluster operations, the exact worker and VPC CNI operations used by this lab,
and pulls from only the four GridGuard ECR repositories. Load-balancer,
dynamic-volume, and upstream-image-import actions remain outside the boundary
because this lab creates none of those resources.

After the EKS Terraform root has a zero-resource state and AWS independently
confirms the cluster, node group, and endpoints are gone, delete this
CloudFormation stack. That detaches and removes the temporary deployment
policy and deletes the now-unused boundary.
