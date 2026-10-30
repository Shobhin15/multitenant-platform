variable "name" {
  description = "Short tenant name, lowercase letters, numbers, and hyphens (for example: acme)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,30}[a-z0-9])?$", var.name))
    error_message = "Tenant name must be 1-32 chars of lowercase letters, numbers, or hyphens."
  }
}

variable "tier" {
  description = "Service tier. Drives the default quota size."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.tier)
    error_message = "Tier must be \"standard\" or \"premium\"."
  }
}

variable "admin_group" {
  description = "Identity provider group that gets admin rights inside this tenant's namespace (mapped from SSO/OIDC)."
  type        = string
}

variable "ingress_namespace" {
  description = "Namespace where the ingress controller runs. Only this namespace may reach tenant pods from outside the tenant."
  type        = string
  default     = "ingress-nginx"
}

variable "quota_overrides" {
  description = "Optional overrides for the tier's default quota."
  type = object({
    requests_cpu    = optional(string)
    requests_memory = optional(string)
    limits_cpu      = optional(string)
    limits_memory   = optional(string)
    pods            = optional(string)
  })
  default = {}
}

variable "extra_labels" {
  description = "Extra labels added to every object the module creates (cost center, owner, and so on)."
  type        = map(string)
  default     = {}
}
