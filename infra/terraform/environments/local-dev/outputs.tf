output "network_boundary" {
  description = "Network zones and cross-boundary service contract."
  value       = module.network_boundary
}

output "observability_foundation" {
  description = "Service endpoint contract for the local telemetry stack."
  value       = module.observability_foundation
}
