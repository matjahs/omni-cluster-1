#!/bin/bash
# Populate Vault with example secrets

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "Error: VAULT_TOKEN environment variable is required"
  echo "Usage: VAULT_TOKEN=<token> ./04-populate-secrets.sh"
  exit 1
fi

echo "==> Creating example secrets in Vault..."

# ArgoCD secrets
echo "Creating ArgoCD admin secret..."
vault kv put secret/argocd/admin \
  password="$(openssl rand -base64 32)"

echo "Creating ArgoCD server secret..."
vault kv put secret/argocd/server \
  secretKey="$(openssl rand -base64 32)"

echo "Creating ArgoCD repository credentials (example)..."
vault kv put secret/argocd/repo \
  url="https://github.com/yourorg/your-repo.git" \
  username="git" \
  password="your-token-here"

# Example app secrets
echo "Creating example app database credentials..."
vault kv put secret/apps/my-app/database \
  host="postgres.database.svc.cluster.local" \
  port="5432" \
  database="myapp" \
  username="myapp_user" \
  password="$(openssl rand -base64 32)"

# Example tenant secrets
echo "Creating example tenant configuration..."
vault kv put secret/tenants/team-a/config \
  api_key="$(openssl rand -base64 32)" \
  webhook_url="https://example.com/webhook" \
  environment="production"

echo "==> Example secrets created successfully!"
echo ""
echo "You can view the secrets with:"
echo "  vault kv get secret/argocd/admin"
echo "  vault kv get secret/apps/my-app/database"
echo "  vault kv get secret/tenants/team-a/config"
