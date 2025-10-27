#!/bin/bash
# Setup Vault policies and roles for multi-tenant access
# This integrates with the existing tenant structure

set -e

cleanup() {
  echo "An error occurred in script: ${BASH_SOURCE[0]} on line: $1 with exit code: $?. Exiting."
  exit 1
}
trap 'cleanup $LINENO' ERR

VAULT_POD="vault-dev-0"
VAULT_NAMESPACE="vault"

echo "===================================="
echo "Setting up Vault Multi-tenancy"
echo "===================================="

# Check if Vault is accessible
if ! kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault status >/dev/null 2>&1; then
  echo "Error: Cannot connect to Vault. Please ensure Vault is running and accessible."
  exit 1
fi

# Get list of tenants from directory structure
TENANTS=$(find tenants -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 -n1 basename)

for TENANT in ${TENANTS}; do
  echo ""
  echo "Setting up Vault for: ${TENANT}"
  echo "------------------------------------"

  # Create Vault policy for this tenant
  echo "Creating Vault policy: ${TENANT}-policy"

  # Create policy file
  POLICY_FILE="/tmp/${TENANT}-policy.hcl"
  cat > "$POLICY_FILE" <<EOF
# Full access to tenant-specific secrets
path "kv/data/${TENANT}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/${TENANT}/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to shared secrets
path "kv/data/shared/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/shared/*" {
  capabilities = ["read", "list"]
}

# Explicitly deny access to other tenants
path "kv/data/team-*" {
  capabilities = ["deny"]
}

# Allow access back to own tenant (more specific path takes precedence)
path "kv/data/${TENANT}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Deny access to platform secrets
path "kv/data/argocd/*" {
  capabilities = ["deny"]
}
EOF

  # Copy policy file to pod
  kubectl cp "$POLICY_FILE" "${VAULT_NAMESPACE}/${VAULT_POD}:/tmp/${TENANT}-policy.hcl"

  # Create policy in Vault
  kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy write "${TENANT}"-policy "/tmp/${TENANT}-policy.hcl"

  # Cleanup
  rm -f "$POLICY_FILE"

  # Create Kubernetes auth role
  echo "Creating Kubernetes auth role: ${TENANT}"
  kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/"${TENANT}" \
    bound_service_account_names="default,external-secrets,${TENANT}-ci" \
    bound_service_account_namespaces="${TENANT}" \
    policies="${TENANT}-policy" \
    ttl="24h"

  echo "✓ ${TENANT} setup complete"
done

# Verification
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
for TENANT in ${TENANTS}; do
  echo "   kubectl exec -n vault vault-dev-0 -- vault kv put kv/${TENANT}/demo password=secret-${TENANT}"
done
echo ""
echo "2. Tenant SecretStores will be created automatically by tenant-baseline chart"
echo ""
echo "3. Test with ExternalSecrets in tenant namespaces"
