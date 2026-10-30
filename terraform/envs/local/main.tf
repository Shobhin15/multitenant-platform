# Onboarding a tenant = adding one entry to tenants.auto.tfvars
# plus one Kustomize overlay under apps/tenant-app/overlays/<name>.

module "tenant" {
  source   = "../../modules/tenant"
  for_each = var.tenants

  name         = each.key
  tier         = each.value.tier
  admin_group  = each.value.admin_group
  extra_labels = each.value.labels
}

output "tenant_namespaces" {
  description = "Namespace created for each tenant."
  value       = { for name, t in module.tenant : name => t.namespace }
}
