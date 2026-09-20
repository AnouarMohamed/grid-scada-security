output "account_id" {
  description = "AWS account selected by the active credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "cluster" {
  description = "Temporary EKS cluster identity and access boundary."
  value = {
    name               = aws_eks_cluster.this.name
    arn                = aws_eks_cluster.this.arn
    version            = aws_eks_cluster.this.version
    public_access_cidr = var.operator_cidr
    private_subnets    = var.cloud_subnet_ids
  }
}

output "kubeconfig_command" {
  description = "Command for the MFA-gated deployment-role profile."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name} --profile gridguard-terraform"
}

output "network_policy" {
  description = "VPC CNI network-policy enforcement configuration."
  value = {
    addon_version = aws_eks_addon.vpc_cni.addon_version
    enabled       = true
    mode          = "strict"
  }
}

output "estimated_billable_features" {
  description = "Cost-bearing features to remove immediately after evidence capture."
  value = {
    eks_clusters        = 1
    on_demand_nodes     = var.node_count
    interface_endpoints = length(local.interface_endpoint_services)
    endpoint_enis       = length(local.interface_endpoint_services) * length(var.cloud_subnet_ids)
    control_plane_logs  = true
    nat_gateways        = 0
    load_balancers      = 0
    public_services     = 0
  }
}

