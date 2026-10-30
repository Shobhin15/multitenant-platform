# Architecture and design decisions

## Isolation model: namespace per tenant

Each tenant gets one namespace, `tenant-<name>`. It's the cheapest isolation model that still gives real boundaries, and it's how most SaaS platforms start before they need a cluster per tenant.

| Layer | Control | Where |
|---|---|---|
| Compute | `ResourceQuota` (CPU, memory, pod count) and `LimitRange` defaults | `terraform/modules/tenant/main.tf` |
| Network | Default deny for ingress and egress; allow same-tenant, DNS, and the ingress controller only | `kubernetes_network_policy_v1.*` |
| Workload security | Pod Security Admission `restricted`; non-root, read-only root filesystem, no capabilities | namespace labels + `apps/tenant-app/base/deployment.yaml` |
| Access | Tenant SSO group bound to the built-in `admin` role inside its namespace only | `kubernetes_role_binding_v1.tenant_admin` |
| Delivery | Argo CD `AppProject` limits tenant apps to `tenant-*` and blocks quota and network-policy edits | `argocd/project.yaml` |
| Exposure | No `LoadBalancer` or `NodePort` services allowed per tenant; all traffic goes through the shared ingress | quota `services.loadbalancers = 0` |

### Why Terraform owns the namespace and Argo CD owns the app

The platform team controls the guardrails (quota, network policy, RBAC), so those live in Terraform and change through platform pull requests. Tenants control their own app, so it lives in Git and Argo CD syncs it. Argo CD runs with `CreateNamespace=false`, and the `AppProject` blacklist stops a tenant's manifests from loosening their own limits.

### Noisy-neighbor protection

- Quotas cap what one tenant can request.
- `LimitRange` defaults make sure pods without explicit requests still count against the quota.
- The HPA scales each tenant independently, inside its own quota.
- Topology spread keeps one tenant's replicas from piling onto a single node.

## Moving this to EKS

| Local (kind) | AWS (EKS) |
|---|---|
| ingress-nginx on host ports | AWS Load Balancer Controller with one ALB and host-based routing per tenant |
| kindnet network policies | VPC CNI with network policy enabled, or Calico |
| Local Terraform state | S3 backend with DynamoDB state locking |
| `admin_group` from a local file | Group mapped from Okta or IAM Identity Center through EKS access entries |
| Tenant service account | IRSA or EKS Pod Identity, scoped to the tenant's own S3 prefix and secrets |
| `*.localtest.me` hosts | Route 53 records per tenant, TLS from ACM |

## What a production version would add

- Per-tenant cost reporting from the `cost-center` label (Kubecost or AWS split cost allocation)
- Separate node pools for premium tenants with taints and tolerations
- Backups per tenant namespace (Velero)
