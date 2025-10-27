#!/usr/bin/env bash
# Multi-tenant user management helper for ArgoCD + Dex + Vault
# Requires: argocd CLI logged in as platform admin, kubectl context, vault CLI (via kubectl exec), GitHub PAT (optional).
set -euo pipefail

VAULT_POD=${VAULT_POD:-vault-dev-0}
VAULT_NS=${VAULT_NS:-vault}
GITHUB_ORG=${GITHUB_ORG:-your-org}
ARGOCD_SERVER=${ARGOCD_SERVER:-argocd.example.com}

usage() {
  cat <<EOF
User Management Script
Usage: $0 <command> [args]
Commands:
  onboard <github-username> <tenant> <role>    Add user to GitHub team and list ArgoCD visibility (requires GH token)
  offboard <github-username> <tenant> <role>   Remove user from team
  list-teams                                   List GitHub teams relevant to tenancy
  show-user <github-username>                  Show teams for user
  rotate-argocd-admin                          Rotate ArgoCD admin password (stores in Vault path kv/argocd/admin)
  rotate-dex-client                            Rotate Dex static client secret (updates Vault + restart)
  show-rbac                                    Show current ArgoCD RBAC policy
  test-login                                   Show current session user groups via argocd CLI
  help                                         This help
Env Vars:
  GITHUB_TOKEN  GitHub PAT with read:org, admin:org (for team membership changes)
  GITHUB_ORG    GitHub organization (default: your-org)
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }; }
for c in kubectl argocd; do require $c; done

github_api() { curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$1"; }
team_slug() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

onboard() {
  [[ $# -eq 3 ]] || { echo "onboard requires <github-username> <tenant> <role>"; exit 1; }
  local user=$1 tenant=$2 role=$3
  [[ -n ${GITHUB_TOKEN:-} ]] || { echo "GITHUB_TOKEN required"; exit 1; }
  local team="${tenant}-${role}"; local slug; slug=$(team_slug "$team")
  echo "Adding user $user to team $team"
  github_api "https://api.github.com/orgs/$GITHUB_ORG/teams/$slug/memberships/$user" -X PUT -d '{"role":"member"}' || true
  echo "Done. User should appear in Dex after next login."
}

offboard() {
  [[ $# -eq 3 ]] || { echo "offboard requires <github-username> <tenant> <role>"; exit 1; }
  local user=$1 tenant=$2 role=$3
  [[ -n ${GITHUB_TOKEN:-} ]] || { echo "GITHUB_TOKEN required"; exit 1; }
  local team="${tenant}-${role}"; local slug; slug=$(team_slug "$team")
  echo "Removing user $user from team $team"
  github_api "https://api.github.com/orgs/$GITHUB_ORG/teams/$slug/memberships/$user" -X DELETE || true
  echo "Done. User access will drop after token refresh."
}

list-teams() {
  [[ -n ${GITHUB_TOKEN:-} ]] || { echo "GITHUB_TOKEN required"; exit 1; }
  github_api "https://api.github.com/orgs/$GITHUB_ORG/teams?per_page=100" | jq -r '.[].slug' | grep -E 'team-(a|b)-(admin|developers|viewers)' || true
}

show-user() {
  [[ $# -eq 1 ]] || { echo "show-user requires <github-username>"; exit 1; }
  [[ -n ${GITHUB_TOKEN:-} ]] || { echo "GITHUB_TOKEN required"; exit 1; }
  github_api "https://api.github.com/orgs/$GITHUB_ORG/members/$1" || echo "User not found or no access"
}

rotate-argocd-admin() {
  local newpass; newpass=$(openssl rand -base64 24)
  echo "Rotating ArgoCD admin password"
  kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault kv put kv/argocd/admin admin.password="$newpass" admin.passwordMtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  echo "Update ExternalSecret will sync; force restart: kubectl -n argocd rollout restart deployment argocd-server"
  echo "New password stored in Vault: kv/argocd/admin"
}

rotate-dex-client() {
  local newsecret; newsecret=$(openssl rand -hex 32)
  echo "Rotating Dex static client secret"
  kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault kv put kv/argocd/dex dex.github.staticClientSecret="$newsecret" || true
  echo "Restart ArgoCD server to apply: kubectl -n argocd rollout restart deployment argocd-server"
}

show-rbac() { kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}' | sed 's/\\n/\n/g' | head -n 50; }

test-login() { argocd account get-user-info || echo "Not logged in"; }

case ${1:-help} in
  onboard) shift; onboard "$@" ;;
  offboard) shift; offboard "$@" ;;
  list-teams) list-teams ;;
  show-user) shift; show-user "$@" ;;
  rotate-argocd-admin) rotate-argocd-admin ;;
  rotate-dex-client) rotate-dex-client ;;
  show-rbac) show-rbac ;;
  test-login) test-login ;;
  help|*) usage ;;
 esac
