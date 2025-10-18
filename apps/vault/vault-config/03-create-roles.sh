#!/bin/bash
# Create Kubernetes auth roles for service accounts

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable is required"
  echo "Usage: VAULT_TOKEN=<token> ./03-create-roles.sh"
  exit 1
fi

echo "==> Creating ArgoCD role..."
vault write auth/kubernetes/role/argocd \
  bound_service_account_names=argocd-server,argocd-application-controller,argocd-repo-server \
  bound_service_account_namespaces=argocd \
  policies=argocd \
  ttl=1h

echo "==> Creating External Secrets Operator role..."
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets,external-secrets-operator \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h

echo "==> Creating default app role (for all namespaces)..."
vault write auth/kubernetes/role/app \
  bound_service_account_names=default \
  bound_service_account_namespaces='*' \
  policies=apps \
  ttl=24h

echo "==> Creating tenant role (for tenant namespaces)..."
vault write auth/kubernetes/role/tenant \
  bound_service_account_names=default \
  bound_service_account_namespaces='team-*' \
  policies=tenants \
  ttl=24h

echo "==> Roles created successfully!"
echo ""
echo "Created roles:"
echo "  - argocd: For ArgoCD service accounts in argocd namespace"
echo "  - external-secrets: For ESO service accounts in external-secrets namespace"
echo "  - app: For default service accounts in any namespace"
echo "  - tenant: For default service accounts in team-* namespaces"
