mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "227755136916"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = data.aws_eks_addon_version.vpc_cni
  values = {
    version = "v1.21.1-eksbuild.1"
  }
}

variables {
  vpc_id                            = "vpc-0123456789abcdef0"
  cloud_subnet_ids                  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  cloud_subnet_cidrs                = ["10.40.10.0/24", "10.40.11.0/24"]
  cloud_route_table_id              = "rtb-0123456789abcdef0"
  operator_cidr                     = "203.0.113.10/32"
  cluster_admin_principal_arn       = "arn:aws:iam::227755136916:role/gridguard-aws-sandbox-foundation-deploy"
  eks_role_permissions_boundary_arn = "arn:aws:iam::227755136916:policy/gridguard/gridguard-aws-eks-lab-role-boundary"
}

run "secure_single_cluster_plan" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.version == "1.36"
    error_message = "The EKS lab must use the reviewed standard-support version."
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.10/32"])
    )
    error_message = "The API endpoint must be private-capable and public only to the operator /32."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2
    error_message = "The bounded exercise must use exactly two workers."
  }

  assert {
    condition = (
      aws_iam_role.cluster.permissions_boundary == var.eks_role_permissions_boundary_arn &&
      aws_iam_role.nodes.permissions_boundary == var.eks_role_permissions_boundary_arn
    )
    error_message = "Both EKS runtime roles must use the reviewed boundary."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 6
    error_message = "Private workers require the six reviewed interface endpoints."
  }

  assert {
    condition     = strcontains(aws_eks_addon.vpc_cni.configuration_values, "strict")
    error_message = "VPC CNI network-policy enforcement must start in strict mode."
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit", "authenticator"])
    error_message = "EKS API, audit, and authenticator logs must be enabled."
  }
}
