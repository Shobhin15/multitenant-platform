CLUSTER      ?= platform
# Pinned so ingress-nginx and Argo CD versions below are known to work together.
KIND_IMAGE   ?= kindest/node:v1.31.4
TF_DIR       := terraform/envs/local
OVERLAYS     := $(wildcard apps/tenant-app/overlays/*)
INGRESS_URL  := https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
ARGOCD_URL   := https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.1/manifests/install.yaml

.PHONY: up cluster ingress argocd tenants apps validate test down

## Bring the whole stack up locally: kind, ingress, Argo CD, tenants, apps
up: cluster ingress argocd tenants apps

cluster:
	kind create cluster --config kind/cluster.yaml --image $(KIND_IMAGE)

ingress:
	kubectl apply -f $(INGRESS_URL)
	kubectl wait -n ingress-nginx --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller --timeout=180s

argocd:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f $(ARGOCD_URL)
	kubectl wait -n argocd --for=condition=available deploy --all --timeout=300s

## Create tenant namespaces, quotas, network policies, and RBAC
tenants:
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) apply -auto-approve

## Let Argo CD deploy one app per tenant overlay
apps:
	kubectl apply -f argocd/project.yaml -f argocd/applicationset.yaml

## Same checks CI runs, no cluster needed
validate:
	terraform fmt -check -recursive terraform
	terraform -chdir=$(TF_DIR) init -backend=false
	terraform -chdir=$(TF_DIR) validate
	@for o in $(OVERLAYS); do \
	  echo "== $$o"; \
	  kustomize build $$o | kubeconform -strict -summary -kubernetes-version 1.30.0 -; \
	done
	kubeconform -strict -summary \
	  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
	  argocd/

## Prove isolation: acme can reach acme, but not globex
test:
	curl -sf http://acme.localtest.me
	curl -sf http://globex.localtest.me
	kubectl -n tenant-acme run probe --rm -i --restart=Never --image=busybox:1.36 \
	  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"busybox:1.36","command":["wget","-qO-","-T","3","http://tenant-app.tenant-globex"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
	  && echo "FAIL: cross-tenant traffic allowed" && exit 1 \
	  || echo "PASS: cross-tenant traffic blocked"

down:
	kind delete cluster --name $(CLUSTER)
