data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}

locals {
  name = "${var.project_name}-${var.environment}"
  availability_zones = (
    length(var.availability_zones) == 2
    ? var.availability_zones
    : slice(data.aws_availability_zones.available.names, 0, 2)
  )

  public_subnets = {
    for index, az in local.availability_zones : az => cidrsubnet(var.vpc_cidr, 8, index)
  }
  cloud_subnets = {
    for index, az in local.availability_zones : az => cidrsubnet(var.vpc_cidr, 8, index + 10)
  }
  ot_subnets = {
    for index, az in local.availability_zones : az => cidrsubnet(var.vpc_cidr, 8, index + 20)
  }

  ecr_repositories  = toset(["power-sim", "modbus-ingestor", "influxdb", "grafana"])
  endpoint_services = toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager"])
  service_names     = toset(["power-sim", "modbus-ingestor", "influxdb", "grafana"])
  stateful_services = toset(["influxdb", "grafana"])

  grafana_listener_port     = var.grafana_public ? 443 : 80
  grafana_listener_protocol = var.grafana_public ? "HTTPS" : "HTTP"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = var.github_repository
  }

  account_iam_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
  expected_github_oidc_provider_arn = (
    "${local.account_iam_prefix}:oidc-provider/token.actions.githubusercontent.com"
  )
  account_policy_prefix = "${local.account_iam_prefix}:policy/"
  regional_acm_prefix = (
    "arn:${data.aws_partition.current.partition}:acm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:certificate/"
  )
}

resource "terraform_data" "invariants" {
  input = {
    enable_runtime           = var.enable_runtime
    enable_vpc_endpoints     = var.enable_vpc_endpoints
    grafana_public           = var.grafana_public
    enable_github_oidc_role  = var.enable_github_oidc_role
    create_github_oidc       = var.create_github_oidc_provider
    github_oidc_provider_arn = var.github_oidc_provider_arn
    grafana_certificate_arn  = var.grafana_certificate_arn
    github_deploy_policy_arn = var.github_deploy_policy_arn
  }

  lifecycle {
    precondition {
      condition     = !var.enable_runtime || var.enable_vpc_endpoints
      error_message = "enable_runtime requires enable_vpc_endpoints so isolated tasks can pull images and logs."
    }

    precondition {
      condition     = !var.grafana_public || var.enable_runtime
      error_message = "grafana_public has no effect unless enable_runtime is true."
    }

    precondition {
      condition     = !var.grafana_public || try(length(var.grafana_certificate_arn) > 0, false)
      error_message = "Public Grafana requires grafana_certificate_arn for HTTPS."
    }

    precondition {
      condition     = !(var.create_github_oidc_provider && var.github_oidc_provider_arn != null)
      error_message = "Create the GitHub OIDC provider or supply its ARN, not both."
    }

    precondition {
      condition = (
        !var.enable_github_oidc_role ||
        var.create_github_oidc_provider ||
        var.github_oidc_provider_arn != null
      )
      error_message = "The GitHub role requires create_github_oidc_provider or github_oidc_provider_arn."
    }

    precondition {
      condition     = var.github_deploy_policy_arn == null || var.enable_github_oidc_role
      error_message = "github_deploy_policy_arn requires enable_github_oidc_role to be true."
    }

    precondition {
      condition = (
        var.github_oidc_provider_arn == null ||
        var.github_oidc_provider_arn == local.expected_github_oidc_provider_arn
      )
      error_message = "github_oidc_provider_arn must be the GitHub Actions provider in the selected AWS account."
    }

    precondition {
      condition = (
        var.github_deploy_policy_arn == null ||
        startswith(var.github_deploy_policy_arn, local.account_policy_prefix)
      )
      error_message = "github_deploy_policy_arn must identify an account-managed policy in the selected AWS account."
    }

    precondition {
      condition = (
        var.github_role_permissions_boundary_arn == null ||
        startswith(var.github_role_permissions_boundary_arn, local.account_policy_prefix)
      )
      error_message = "github_role_permissions_boundary_arn must identify a policy in the selected AWS account."
    }

    precondition {
      condition = (
        var.grafana_certificate_arn == null ||
        startswith(var.grafana_certificate_arn, local.regional_acm_prefix)
      )
      error_message = "grafana_certificate_arn must identify a certificate in the selected AWS account and region."
    }
  }
}
