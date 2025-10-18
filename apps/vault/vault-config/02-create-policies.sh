#!/bin/bash
# Create Vault policies for different use cases

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable is required"
  echo "Usage: VAULT_TOKEN=<token> ./02-create-policies.sh"
  exit 1
fi

echo "==> Creating ArgoCD policy..."
vault policy write argocd - <<POLICY
# Allow ArgoCD to read secrets for all applications
path "secret/data/argocd/*" {
  capabilities = ["read", "list"]
}

# Allow ArgoCD to read app secrets
path "secret/data/apps/*" {
  capabilities = ["read", "list"]
}
POLICY

echo "==> Creating application policy..."
vault policy write apps - <<POLICY
# Allow applications to read their own secrets
path "secret/data/apps/{{identity.entity.aliases.AUTH_MOUNT_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}
POLICY

echo "==> Creating tenant policy template..."
vault policy write tenants - <<POLICY
# Allow tenants to manage their own secrets
path "secret/data/tenants/{{identity.entity.aliases.AUTH_MOUNT_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow reading metadata
path "secret/metadata/tenants/{{identity.entity.aliases.AUTH_MOUNT_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["list"]
}
POLICY

echo "==> Creating external-secrets-operator policy..."
vault policy write external-secrets - <<POLICY
# Allow ESO to read secrets for all namespaces
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}
POLICY

echo "==> Policies created successfully!"
echo ""
echo "Created policies:"
echo "  - argocd: Read access to argocd/* and apps/*"
echo "  - apps: Read access to apps/<namespace>/*"
echo "  - tenants: Full access to tenants/<namespace>/*"
echo "  - external-secrets: Read access to all secrets"
