#!/bin/bash
# Enable and configure Kubernetes auth method in Vault

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable is required"
  echo "Usage: VAULT_TOKEN=<token> ./01-enable-k8s-auth.sh"
  exit 1
fi

echo "==> Enabling Kubernetes auth method..."
vault auth enable -path=kubernetes kubernetes || echo "Kubernetes auth already enabled"

echo "==> Configuring Kubernetes auth method..."
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"


vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$SA_CA_CRT"

echo "==> Kubernetes auth method configured successfully!"
echo ""
echo "Next steps:"
echo "1. Create Vault policies (run 02-create-policies.sh)"
echo "2. Create Kubernetes auth roles (run 03-create-roles.sh)"
