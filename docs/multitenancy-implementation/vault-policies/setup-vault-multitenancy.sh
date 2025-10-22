#!/bin/bash
# Setup Vault policies and roles for multi-tenant access

set -e

VAULT_POD="vault-dev-0"
VAULT_NAMESPACE="vault"

echo "===================================="
echo "Setting up Vault Multi-tenancy"
echo "===================================="

# ============================================
# Team A - Vault Policy
# ============================================
echo ""
echo "Creating Vault policy for team-a..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy write team-a-policy - <<EOF
# Full access to team-a secrets
path "kv/data/team-a/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/team-a/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to shared secrets (optional)
path "kv/data/shared/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/shared/*" {
  capabilities = ["read", "list"]
}

# Deny access to other teams
path "kv/data/team-b/*" {
  capabilities = ["deny"]
}

path "kv/data/argocd/*" {
  capabilities = ["deny"]
}
EOF

# ============================================
# Team A - Kubernetes Auth Role
# ============================================
echo "Creating Kubernetes auth role for team-a..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/team-a \
  bound_service_account_names="external-secrets,team-a-ci,default" \
  bound_service_account_namespaces="team-a" \
  policies="team-a-policy" \
  ttl="24h"

# ============================================
# Team B - Vault Policy
# ============================================
echo ""
echo "Creating Vault policy for team-b..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy write team-b-policy - <<EOF
# Full access to team-b secrets
path "kv/data/team-b/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/team-b/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to shared secrets (optional)
path "kv/data/shared/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/shared/*" {
  capabilities = ["read", "list"]
}

# Deny access to other teams
path "kv/data/team-a/*" {
  capabilities = ["deny"]
}

path "kv/data/argocd/*" {
  capabilities = ["deny"]
}
EOF

# ============================================
# Team B - Kubernetes Auth Role
# ============================================
echo "Creating Kubernetes auth role for team-b..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/team-b \
  bound_service_account_names="external-secrets,team-b-ci,default" \
  bound_service_account_namespaces="team-b" \
  policies="team-b-policy" \
  ttl="24h"

# ============================================
# Verify Setup
# ============================================
echo ""
echo "===================================="
echo "Verification"
echo "===================================="
echo ""
echo "Vault Policies:"
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy list

echo ""
echo "Kubernetes Auth Roles:"
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault list auth/kubernetes/role

echo ""
echo "===================================="
echo "Setup Complete!"
echo "===================================="
echo ""
echo "Next steps:"
echo "1. Create sample secrets for each tenant:"
echo "   kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-a/demo key=value"
echo "   kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-b/demo key=value"
echo ""
echo "2. Deploy tenant SecretStores (see tenant-rbac/ directory)"
echo ""
echo "3. Test access with ExternalSecrets"
