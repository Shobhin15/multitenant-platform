locals {
  namespace = "tenant-${var.name}"

  tier_quota = {
    standard = {
      requests_cpu    = "2"
      requests_memory = "4Gi"
      limits_cpu      = "4"
      limits_memory   = "8Gi"
      pods            = "20"
    }
    premium = {
      requests_cpu    = "8"
      requests_memory = "16Gi"
      limits_cpu      = "16"
      limits_memory   = "32Gi"
      pods            = "100"
    }
  }

  # Tier defaults, with any per-tenant overrides layered on top.
  quota = merge(
    local.tier_quota[var.tier],
    { for k, v in var.quota_overrides : k => v if v != null }
  )

  labels = merge(
    {
      "app.kubernetes.io/managed-by" = "terraform"
      "platform.example.io/tenant"   = var.name
      "platform.example.io/tier"     = var.tier
    },
    var.extra_labels
  )
}

# One namespace per tenant is the isolation boundary for everything below.
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace
    labels = merge(local.labels, {
      # Pod Security Admission: block privileged pods in tenant namespaces.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    })
  }
}

# Hard ceiling so one noisy tenant cannot starve the others.
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "tenant-quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    hard = {
      "requests.cpu"           = local.quota.requests_cpu
      "requests.memory"        = local.quota.requests_memory
      "limits.cpu"             = local.quota.limits_cpu
      "limits.memory"          = local.quota.limits_memory
      "pods"                   = local.quota.pods
      "services.loadbalancers" = "0"
      "services.nodeports"     = "0"
    }
  }
}

# Default requests/limits so pods without them still count against the quota.
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "tenant-defaults"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Start from deny-all, then open only what each tenant needs.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# Pods inside the same tenant can talk to each other; other tenants cannot.
resource "kubernetes_network_policy_v1" "allow_same_tenant" {
  metadata {
    name      = "allow-same-tenant"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {}
      }
    }

    egress {
      to {
        pod_selector {}
      }
    }
  }
}

# Only the ingress controller may reach tenant pods from outside the namespace.
resource "kubernetes_network_policy_v1" "allow_from_ingress" {
  metadata {
    name      = "allow-from-ingress-controller"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_namespace
          }
        }
      }
    }
  }
}

# Every pod still needs DNS.
resource "kubernetes_network_policy_v1" "allow_dns" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# Tenant admins get full control inside their own namespace and nothing outside it.
resource "kubernetes_role_binding_v1" "tenant_admin" {
  metadata {
    name      = "tenant-admin"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  subject {
    kind      = "Group"
    name      = var.admin_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# Workload identity for the tenant's apps. No cluster-wide permissions.
resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = "tenant-app"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  automount_service_account_token = false
}
