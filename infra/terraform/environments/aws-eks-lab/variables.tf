variable "aws_region" {
  description = "AWS region containing the retained GridGuard VPC."
  type        = string
  default     = "us-east-1"
}

variable "expected_account_id" {
  description = "Account guardrail checked against the active AWS credentials."
  type        = string
  default     = "227755136916"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}

variable "vpc_id" {
  description = "Retained GridGuard VPC identifier."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC identifier."
  }
}

variable "vpc_cidr" {
  description = "CIDR of the retained GridGuard VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "cloud_subnet_ids" {
  description = "Two private cloud-core subnet IDs in separate availability zones."
  type        = list(string)

  validation {
    condition = (
      length(var.cloud_subnet_ids) == 2 &&
      alltrue([for id in var.cloud_subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))])
    )
    error_message = "cloud_subnet_ids must contain exactly two subnet IDs."
  }
}

variable "cloud_subnet_cidrs" {
  description = "CIDRs matching cloud_subnet_ids; used to constrain endpoint ingress."
  type        = list(string)

  validation {
    condition     = length(var.cloud_subnet_cidrs) == 2
    error_message = "cloud_subnet_cidrs must contain exactly two CIDRs."
  }
}

variable "cloud_route_table_id" {
  description = "Cloud-core route table receiving the S3 gateway endpoint."
  type        = string

  validation {
    condition     = can(regex("^rtb-[0-9a-f]+$", var.cloud_route_table_id))
    error_message = "cloud_route_table_id must be an AWS route-table identifier."
  }
}

variable "operator_cidr" {
  description = "Current operator public IPv4 address as a single-host /32 CIDR."
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_cidr, 0)) && endswith(var.operator_cidr, "/32")
    error_message = "operator_cidr must be a valid single-host IPv4 /32 CIDR."
  }
}

variable "cluster_admin_principal_arn" {
  description = "MFA-gated IAM role granted temporary Kubernetes cluster-admin access."
  type        = string
}

variable "eks_role_permissions_boundary_arn" {
  description = "Temporary permissions boundary for the EKS service and node roles."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version in standard support."
  type        = string
  default     = "1.36"

  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "Use an EKS Kubernetes version currently in standard support."
  }
}

variable "node_instance_types" {
  description = "On-Demand EC2 types for the short-lived managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_count" {
  description = "Fixed worker count for the bounded two-AZ exercise."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count == 2
    error_message = "The evidence run requires exactly two workers, one capacity target per AZ."
  }
}

variable "log_retention_days" {
  description = "Retention for EKS control-plane audit logs."
  type        = number
  default     = 7
}
