locals {
  service_names = sort(keys(var.services))

  host_exposed_services = {
    for name, service in var.services : name => service
    if service.public
  }

  internal_services = {
    for name, service in var.services : name => service
    if !service.public
  }

  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}
