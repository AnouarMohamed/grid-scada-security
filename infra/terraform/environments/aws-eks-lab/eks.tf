resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "this" {
  name                      = local.name
  role_arn                  = aws_iam_role.cluster.arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  deletion_protection       = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = var.cloud_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.operator_cidr]
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster,
    terraform_data.invariants,
  ]
}

resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.operator.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
    env = {
      NETWORK_POLICY_ENFORCING_MODE = "strict"
    }
  })
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-workers"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.cloud_subnet_ids
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_instance_types
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "gridguard.io/environment" = "aws-eks-lab"
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
  ]
}

