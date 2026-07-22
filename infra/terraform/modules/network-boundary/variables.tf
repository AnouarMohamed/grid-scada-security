variable "project_name" {
  description = "Short project identifier."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "zones" {
  description = "Network zones that must remain separate."
  type = map(object({
    cidr            = string
    description     = string
    exposure        = string
    allowed_ingress = list(string)
    allowed_egress  = list(string)
  }))

  validation {
    condition     = length(var.zones) >= 2
    error_message = "At least two zones are required to preserve the OT/cloud boundary."
  }

  validation {
    condition = alltrue([
      for zone in var.zones : contains(["internal", "host-loopback", "private", "public"], zone.exposure)
    ])
    error_message = "zone exposure must be one of: internal, host-loopback, private, public."
  }
}

variable "boundary_services" {
  description = "Services intentionally allowed to connect more than one zone."
  type = map(object({
    description        = string
    connects           = list(string)
    future_replacement = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for service in var.boundary_services : length(service.connects) >= 2
    ])
    error_message = "Every boundary service must connect at least two zones."
  }
}
