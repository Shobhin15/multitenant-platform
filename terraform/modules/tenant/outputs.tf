output "namespace" {
  description = "Namespace created for the tenant."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_account" {
  description = "Service account the tenant's workloads run as."
  value       = kubernetes_service_account_v1.app.metadata[0].name
}

output "quota" {
  description = "Effective resource quota for the tenant."
  value       = local.quota
}
