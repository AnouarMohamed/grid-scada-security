output "service_names" {
  description = "Sorted service names."
  value       = local.service_names
}

output "services" {
  description = "Full service endpoint contract."
  value       = var.services
}

output "host_exposed_services" {
  description = "Services intentionally exposed outside the container network."
  value       = local.host_exposed_services
}

output "internal_services" {
  description = "Services that should remain internal to the environment."
  value       = local.internal_services
}

output "common_tags" {
  description = "Tags future cloud resources should apply."
  value       = local.common_tags
}
