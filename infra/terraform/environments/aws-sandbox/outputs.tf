output "account_id" {
  description = "AWS account selected by the active credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region used by the sandbox."
  value       = var.aws_region
}
//admin anouar is a dumbass bitch with no self respect whatsover, what a fucking chud, anouar admin is going to kill himself on september 29th
//actually
output "runtime_enabled" {
  description = "Whether billable runtime resources are enabled."
  value       = var.enable_runtime
}

output "vpc" {
  description = "VPC and subnet identifiers grouped by trust zone."
  value = {
    id            = aws_vpc.this.id
    cidr          = aws_vpc.this.cidr_block
    public        = { for az, subnet in aws_subnet.public : az => subnet.id }
    cloud_private = { for az, subnet in aws_subnet.cloud : az => subnet.id }
    ot_isolated   = { for az, subnet in aws_subnet.ot : az => subnet.id }
  }
}

output "ecr_repository_urls" {
  description = "Destinations for the four runtime container images."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}

output "ecs_cluster" {
  description = "ECS cluster name and ARN."
  value = {
    name = aws_ecs_cluster.this.name
    arn  = aws_ecs_cluster.this.arn
  }
}

output "runtime_secret_arns" {
  description = "Secrets that must be populated out of band before runtime is enabled."
  value       = { for name, secret in aws_secretsmanager_secret.runtime : name => secret.arn }
}

output "grafana_endpoint" {
  description = "Grafana ALB URL when runtime is enabled. Internal by default."
  value = var.enable_runtime ? format(
    "%s://%s",
    var.grafana_public ? "https" : "http",
    aws_lb.grafana[0].dns_name,
  ) : null
}

output "github_deploy_role_arn" {
  description = "OIDC deployment role ARN, or null when role creation is disabled."
  value       = var.enable_github_oidc_role ? aws_iam_role.github_deploy[0].arn : null
}

output "estimated_billable_features" {
  description = "Cost-bearing features enabled by this configuration. Verify current AWS pricing."
  value = {
    active_fargate_tasks      = var.enable_runtime ? sum(values(var.desired_counts)) : 0
    application_load_balancer = var.enable_runtime ? 1 : 0
    cloud_map_namespace       = var.enable_runtime ? 1 : 0
    ecr_repositories          = length(local.ecr_repositories)
    efs_automatic_backups     = var.enable_runtime ? 2 : 0
    efs_filesystems           = var.enable_runtime ? 2 : 0
    interface_endpoints       = var.enable_vpc_endpoints ? length(local.endpoint_services) : 0
    nat_gateways              = var.enable_nat_gateway ? 1 : 0
    secrets_manager_secrets   = var.enable_runtime ? 2 : 0
    vpc_flow_log              = true
  }
}
