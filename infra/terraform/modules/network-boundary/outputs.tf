output "zone_names" {
  description = "Sorted network zone names."
  value       = local.zone_names
}

output "zones" {
  description = "Network zone contract."
  value       = var.zones
}

output "boundary_service_names" {
  description = "Sorted names of services that intentionally cross zones."
  value       = local.boundary_service_names
}

output "boundary_services" {
  description = "Cross-zone service contract."
  value       = var.boundary_services
}

output "security_invariants" {
  description = "Security rules that must remain true as real cloud resources are added."
  value       = local.security_invariants
}

output "common_tags" {
  description = "Tags future cloud resources should apply."
  value       = local.common_tags
}
