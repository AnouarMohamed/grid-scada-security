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
  description = "Immutable ECR tags used to publish and audit each release. ECS uses image_digests."
  type = object({
    power_sim       = string
    modbus_ingestor = string
    influxdb        = string
    grafana         = string
  })
  default = {
    power_sim       = "0.1.1"
    modbus_ingestor = "0.1.1"
    influxdb        = "2.9.1-gridguard.1"
    grafana         = "12.4.10-gridguard.1"
  }

  validation {
    condition = alltrue([
      for tag in values(var.image_tags) :
      can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", tag)) && lower(tag) != "latest"
    ])
    error_message = "image_tags values must be valid, non-latest ECR tags of at most 128 characters."
  }
}

variable "image_digests" {
  description = "Verified Linux/AMD64 ECR manifest digests selected by ECS task definitions."
  type = object({
    power_sim       = string
    modbus_ingestor = string
    influxdb        = string
    grafana         = string
  })
  default = {
    power_sim       = "sha256:f51d3dd888b3a2a2855bbba40725357a92d91c2a9bd6660fdd8a5a39505a9451"
    modbus_ingestor = "sha256:18e13b46ed9fe4d89290ae8219b6cd897e3a8e3c6675f3069541779b49e2caa7"
    influxdb        = "sha256:66e4f468821b9a47f9eb0808d2e87c70d6ddd92c741450e9d78eff70ae856d67"
    grafana         = "sha256:1fbc7b35e2e71e9ccf8178dc7b05369bc85a9000320ee40031743a868f566c5c"
  }

  validation {
    condition = alltrue([
      for digest in values(var.image_digests) :
      can(regex("^sha256:[0-9a-f]{64}$", digest))
    ])
    error_message = "image_digests values must be lowercase sha256 manifest digests."
  }
}

variable "github_repository" {
  description = "Human-readable GitHub owner/repository used in resource tags."
  type        = string
  default     = "AnouarMohamed/grid-scada-security"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use owner/repository form."
  }
}

variable "github_oidc_subject_repository" {
  description = "Immutable GitHub owner@owner-id/repository@repository-id OIDC subject prefix."
  type        = string
  default     = "AnouarMohamed@235483559/grid-scada-security@1307773501"

  validation {
    condition = can(regex(
      "^[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$",
      var.github_oidc_subject_repository,
    ))
    error_message = "github_oidc_subject_repository must use immutable owner@owner-id/repository@repository-id form."
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

variable "workload_role_permissions_boundary_arn" {
  description = "Required permissions boundary ARN for ECS and VPC Flow Logs workload roles."
  type        = string

  validation {
    condition = can(regex(
      "^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/[A-Za-z0-9_+=,.@/-]+$",
      var.workload_role_permissions_boundary_arn,
    ))
    error_message = "workload_role_permissions_boundary_arn must be an IAM managed-policy ARN."
  }
}
