variable "project_name" {
  description = "Short project identifier."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "services" {
  description = "Observable service endpoints in this environment."
  type = map(object({
    zone        = string
    protocol    = string
    port        = number
    public      = bool
    health_path = string
    description = string
  }))

  validation {
    condition = alltrue([
      for service in var.services : service.port > 0 && service.port <= 65535
    ])
    error_message = "Every service port must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for service in var.services : contains(["http", "https", "tcp"], service.protocol)
    ])
    error_message = "service protocol must be one of: http, https, tcp."
  }
}
