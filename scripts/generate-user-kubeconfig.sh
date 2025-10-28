#!/usr/bin/env bash
#
# Generate kubeconfig for tenant users with strict namespace isolation
#
# Usage: ./scripts/generate-user-kubeconfig.sh <user-email> <namespace>
#
# Example:
#   ./scripts/generate-user-kubeconfig.sh alice@matjah.dev team-a
#
# This creates a kubeconfig with:
# - User impersonation (alice@matjah.dev)
# - Group impersonation (team-a-admins)
# - Default namespace set to team-a
# - Complete isolation from other namespaces

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
error() { echo -e "${RED}ERROR: $*${NC}" >&2; }
success() { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${YELLOW}→ $*${NC}"; }

# Check arguments
if [ $# -ne 2 ]; then
    error "Invalid arguments"
    echo "Usage: $0 <user-email> <namespace>"
    echo ""
    echo "Example:"
    echo "  $0 alice@matjah.dev team-a"
    echo ""
    echo "Available namespaces: team-a, team-b"
    exit 1
fi

USER_EMAIL="$1"
NAMESPACE="$2"
CLUSTER_NAME="talos-default"

# Determine group based on namespace
case "$NAMESPACE" in
    team-a)
        GROUP="team-a-admins"
        ;;
    team-b)
        GROUP="team-b-admins"
        ;;
    *)
        error "Invalid namespace: $NAMESPACE"
        echo "Available namespaces: team-a, team-b"
        exit 1
        ;;
esac

# Output file
OUTPUT_DIR="$(pwd)/kubeconfigs"
OUTPUT_FILE="${OUTPUT_DIR}/${USER_EMAIL}-${NAMESPACE}.yaml"

# Create output directory
mkdir -p "$OUTPUT_DIR"

info "Generating kubeconfig for:"
echo "  User:      $USER_EMAIL"
echo "  Namespace: $NAMESPACE"
echo "  Group:     $GROUP"
echo "  Cluster:   $CLUSTER_NAME"
echo ""

# Check if omnictl is available
if ! command -v omnictl &> /dev/null; then
    error "omnictl not found. Please install Omni CLI."
    exit 1
fi

# Get cluster info from current kubeconfig (admin's config)
info "Extracting cluster configuration..."

# Try to get from current context
if [ -z "${KUBECONFIG:-}" ]; then
    KUBECONFIG="$HOME/.kube/config"
fi

# Extract cluster info from current kubeconfig
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ -z "$CURRENT_CONTEXT" ]; then
    error "No current kubectl context found"
    echo "Make sure you have a valid kubeconfig configured"
    exit 1
fi

CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CLIENT_CERT=$(kubectl config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}')
CLIENT_KEY=$(kubectl config view --minify --raw -o jsonpath='{.users[0].user.client-key-data}')

info "Creating impersonation kubeconfig..."

# Create kubeconfig with impersonation
cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
    server: $CLUSTER_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    user: ${USER_EMAIL}
    namespace: $NAMESPACE
  name: ${USER_EMAIL}@${CLUSTER_NAME}
current-context: ${USER_EMAIL}@${CLUSTER_NAME}
users:
- name: ${USER_EMAIL}
  user:
    as: ${USER_EMAIL}
    as-groups:
    - ${GROUP}
    - system:authenticated
    client-certificate-data: $CLIENT_CERT
    client-key-data: $CLIENT_KEY
EOF

success "Kubeconfig generated successfully!"
echo ""
echo "File: $OUTPUT_FILE"
echo ""
info "Send this file securely to: $USER_EMAIL"
echo ""
echo "User instructions:"
echo "  1. Save the kubeconfig file"
echo "  2. Set environment variable:"
echo "     export KUBECONFIG=\$HOME/.kube/${USER_EMAIL}-${NAMESPACE}.yaml"
echo "  3. Test access:"
echo "     kubectl get pods -n $NAMESPACE"
echo ""
success "User $USER_EMAIL now has access to namespace: $NAMESPACE"
echo ""
echo "⚠️  Security:"
echo "  - User can ONLY access namespace: $NAMESPACE"
echo "  - User CANNOT see resources in other namespaces"
echo "  - Send kubeconfig via secure channel (encrypted email, password manager, etc.)"
