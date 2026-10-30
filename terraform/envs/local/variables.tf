variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the target cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to use. kind names it kind-<cluster-name>."
  type        = string
  default     = "kind-platform"
}

variable "tenants" {
  description = "Tenants to create. The map key is the tenant name."
  type = map(object({
    tier        = string
    admin_group = string
    labels      = optional(map(string), {})
  }))
}
