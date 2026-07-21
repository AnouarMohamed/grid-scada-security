locals {
  zone_names = sort(keys(var.zones))

  boundary_service_names = sort(keys(var.boundary_services))

  security_invariants = [
    "OT simulation services are not exposed directly to the host or internet.",
    "Cloud telemetry services do not initiate arbitrary connections into OT.",
    "Only named boundary services may connect OT and cloud zones.",
    "Secrets and stateful data stay out of version control.",
  ]

  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}
