variable "project_name" {
  description = "Short identifier used in AWS resource names."
  type        = string
  default     = "gridguard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, numbers, or hyphens."
  }
}

variable "environment" {
  description = "Environment identifier used in names and tags."
  type        = string
  default     = "aws-sandbox"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be 2-21 lowercase letters, numbers, or hyphens."
  }
}

variable "aws_region" {
  description = "AWS region in which the sandbox is created."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the sandbox VPC. The layout reserves /24 subnets."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition = try(
      can(cidrnetmask(var.vpc_cidr)) &&
      tonumber(split("/", var.vpc_cidr)[1]) == 16 &&
      can(cidrsubnet(var.vpc_cidr, 8, 20)) &&
      (
        tonumber(split(".", var.vpc_cidr)[0]) == 10 ||
        (
          tonumber(split(".", var.vpc_cidr)[0]) == 172 &&
          tonumber(split(".", var.vpc_cidr)[1]) >= 16 &&
          tonumber(split(".", var.vpc_cidr)[1]) <= 31
        ) ||
        (
          tonumber(split(".", var.vpc_cidr)[0]) == 192 &&
          tonumber(split(".", var.vpc_cidr)[1]) == 168
        )
      ),
      false,
    )
    error_message = "vpc_cidr must be a private IPv4 /16 from which the six /24 subnets can be derived."
  }
}

variable "availability_zones" {
  description = "Exactly two AZ names. Leave empty to select the first two available AZs."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.availability_zones) == 0 ||
      (length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2)
    )
    error_message = "availability_zones must be empty or contain exactly two distinct AZs."
  }
}

variable "enable_runtime" {
  description = "Create billable ALB, EFS, secrets, task definitions, and ECS services."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Create ECR, CloudWatch Logs, Secrets Manager, and S3 endpoints for isolated tasks."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Create one NAT gateway for cloud-private outbound access. OT subnets never use it."
  type        = bool
  default     = false
}

variable "grafana_public" {
  description = "Place Grafana's ALB in public subnets. Requires an ACM certificate."
  type        = bool
  default     = false
}

variable "grafana_certificate_arn" {
  description = "ACM certificate ARN for public Grafana HTTPS. Null for an internal HTTP ALB."
  type        = string
  default     = null
}

variable "operator_cidrs" {
  description = "Restricted IPv4 CIDRs allowed to reach the Grafana listener. Public internet access is rejected."
  type        = list(string)
  default     = ["10.40.0.0/16"]

  validation {
    condition = (
      length(var.operator_cidrs) > 0 &&
      alltrue([
        for cidr in var.operator_cidrs : try(
          can(cidrnetmask(cidr)) &&
          tonumber(split("/", cidr)[1]) >= 8 &&
          tonumber(split("/", cidr)[1]) <= 32,
          false,
        )
      ])
    )
    error_message = "operator_cidrs must contain valid IPv4 CIDRs with prefix lengths from /8 to /32."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention for application and VPC flow logs."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch-supported retention value."
  }
}

variable "desired_counts" {
  description = "Desired ECS task counts used only when enable_runtime is true."
  type = object({
    power_sim       = number
    modbus_ingestor = number
    influxdb        = number
    grafana         = number
  })
  default = {
    power_sim       = 0
    modbus_ingestor = 0
    influxdb        = 0
    grafana         = 0
  }

  validation {
    condition = (
      alltrue([for count in values(var.desired_counts) : count >= 0 && count <= 2 && floor(count) == count]) &&
      var.desired_counts.influxdb <= 1 &&
      var.desired_counts.grafana <= 1
    )
    error_message = "desired_counts must be integers from 0-2; stateful InfluxDB and Grafana counts cannot exceed 1."
  }
}

variable "image_tags" {
  description = "ECR image tags selected by ECS task definitions. Use immutable release tags."
  type = object({
    power_sim       = string
    modbus_ingestor = string
    influxdb        = string
    grafana         = string
  })
  default = {
    power_sim       = "0.1.0"
    modbus_ingestor = "0.1.0"
    influxdb        = "2.9.0"
    grafana         = "12.4.10"
  }

  validation {
    condition = alltrue([
      for tag in values(var.image_tags) :
      can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", tag)) && lower(tag) != "latest"
    ])
    error_message = "image_tags values must be valid, non-latest ECR tags of at most 128 characters."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to request deployment credentials."
  type        = string
  default     = "AnouarMohamed/grid-scada-security"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use owner/repository form."
  }
}

variable "github_environments" {
  description = "GitHub environments trusted by the deployment role."
  type        = set(string)
  default     = ["sandbox", "staging", "production"]

  validation {
    condition     = length(var.github_environments) > 0
    error_message = "github_environments must contain at least one environment."
  }
}

variable "enable_github_oidc_role" {
  description = "Create the GitHub Actions deployment role. It has no permissions by default."
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Enable only if it does not exist."
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com IAM OIDC provider."
  type        = string
  default     = null
}

variable "github_deploy_policy_arn" {
  description = "Account-managed policy to attach to the GitHub role. Null leaves it permissionless."
  type        = string
  default     = null
}

variable "github_role_permissions_boundary_arn" {
  description = "Optional permissions boundary ARN for the GitHub deployment role."
  type        = string
  default     = null
}
