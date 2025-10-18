#!/bin/bash
# Master setup script for Vault configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Vault Configuration Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if [ -z "$VAULT_TOKEN" ]; then
  echo -e "${RED}Error: VAULT_TOKEN environment variable is required${NC}"
  echo ""
  echo "Please set VAULT_TOKEN from vault.env:"
  echo "  export VAULT_TOKEN=<root-token>"
  echo ""
  exit 1
fi

if ! command -v vault &> /dev/null; then
  echo -e "${RED}Error: vault CLI not found${NC}"
  echo "Please install Vault CLI: https://www.vaultproject.io/downloads"
  exit 1
fi

# Test Vault connectivity
echo "Testing Vault connectivity..."
if ! vault status &> /dev/null; then
  echo -e "${RED}Error: Cannot connect to Vault at $VAULT_ADDR${NC}"
  echo ""
  echo "Make sure Vault is accessible:"
  echo "  kubectl port-forward -n vault svc/vault 8200:8200"
  echo "  export VAULT_ADDR=http://localhost:8200"
  exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Step 1: Enable Kubernetes auth
echo -e "${YELLOW}Step 1/5: Enabling Kubernetes authentication...${NC}"
"$SCRIPT_DIR/01-enable-k8s-auth.sh"
echo -e "${GREEN}✓ Kubernetes auth enabled${NC}"
echo ""

# Step 2: Create policies
echo -e "${YELLOW}Step 2/5: Creating Vault policies...${NC}"
"$SCRIPT_DIR/02-create-policies.sh"
echo -e "${GREEN}✓ Policies created${NC}"
echo ""

# Step 3: Create roles
echo -e "${YELLOW}Step 3/5: Creating Kubernetes auth roles...${NC}"
"$SCRIPT_DIR/03-create-roles.sh"
echo -e "${GREEN}✓ Roles created${NC}"
echo ""

# Step 4: Populate example secrets
echo -e "${YELLOW}Step 4/5: Populating example secrets...${NC}"
"$SCRIPT_DIR/04-populate-secrets.sh"
echo -e "${GREEN}✓ Example secrets created${NC}"
echo ""

# Step 5: Deploy SecretStores
echo -e "${YELLOW}Step 5/5: Deploying SecretStores...${NC}"
kubectl apply -f "$SCRIPT_DIR/cluster-secret-store.yaml"
kubectl apply -f "$SCRIPT_DIR/secret-store-argocd.yaml"
echo -e "${GREEN}✓ SecretStores deployed${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Vault is now configured with:"
echo "  ✓ Kubernetes authentication"
echo "  ✓ Policies for ArgoCD, apps, and tenants"
echo "  ✓ Kubernetes auth roles"
echo "  ✓ Example secrets"
echo "  ✓ SecretStores for External Secrets Operator"
echo ""
echo "Next steps:"
echo "  1. Deploy example ExternalSecrets:"
echo "     kubectl apply -f $SCRIPT_DIR/external-secret-example-argocd.yaml"
echo ""
echo "  2. Verify secrets are synced:"
echo "     kubectl get externalsecrets -A"
echo "     kubectl get secrets -n argocd argocd-secret"
echo ""
echo "  3. Read the full documentation:"
echo "     cat $SCRIPT_DIR/README.md"
echo ""
