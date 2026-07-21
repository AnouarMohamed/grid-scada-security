variable "project_name" {
  description = "Short project identifier used in generated names and metadata."
  type        = string
  default     = "gridguard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, numbers, or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "local-dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,31}$", var.environment))
    error_message = "environment must be 2-32 lowercase letters, numbers, or hyphens."
  }
}
