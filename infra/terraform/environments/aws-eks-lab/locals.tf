data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

locals {
  name = "gridguard-aws-eks-lab"

  interface_endpoint_services = toset([
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "eks",
    "logs",
    "sts",
  ])

  common_tags = {
    Project     = "gridguard"
    Environment = "aws-eks-lab"
    ManagedBy   = "terraform"
    Repository  = "AnouarMohamed/grid-scada-security"
    Expires     = "same-day-teardown"
  }
}

resource "terraform_data" "invariants" {
  input = {
    account_id         = data.aws_caller_identity.current.account_id
    cluster_name       = local.name
    kubernetes_version = var.kubernetes_version
    node_count         = var.node_count
    operator_cidr      = var.operator_cidr
    subnet_ids         = var.cloud_subnet_ids
  }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "The active AWS credentials do not match expected_account_id."
    }

    precondition {
      condition     = length(var.cloud_subnet_ids) == length(var.cloud_subnet_cidrs)
      error_message = "Every private subnet must have one matching CIDR."
    }

    precondition {
      condition = startswith(
        var.cluster_admin_principal_arn,
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/",
      )
      error_message = "cluster_admin_principal_arn must be a role in the selected account."
    }

    precondition {
      condition = startswith(
        var.eks_role_permissions_boundary_arn,
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/",
      )
      error_message = "eks_role_permissions_boundary_arn must be a policy in the selected account."
    }
  }
}

