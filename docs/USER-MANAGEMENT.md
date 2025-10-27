# User Management (Multi-Tenant SSO)

This guide explains how to onboard/offboard users and rotate credentials for ArgoCD + Dex + Vault.

## Prerequisites
- GitHub organization with teams: team-a-admins, team-a-developers, team-a-viewers, team-b-admins, team-b-developers, team-b-viewers
- GitHub OAuth App (clientID/clientSecret) configured in Vault at kv/argocd/dex
- ArgoCD + Dex deployed (config.yaml includes dex.config)
- Vault + External Secrets Operator running
- GitHub PAT (env GITHUB_TOKEN) with scopes: read:org, admin:org (only needed for automated team membership changes)

## Script Location
```
scripts/user-management.sh
```
Run with bash or make it available in PATH.

## Commands
```
./scripts/user-management.sh help
./scripts/user-management.sh onboard <github-username> <tenant> <role>
./scripts/user-management.sh offboard <github-username> <tenant> <role>
./scripts/user-management.sh list-teams
./scripts/user-management.sh show-user <github-username>
./scripts/user-management.sh rotate-argocd-admin
./scripts/user-management.sh rotate-dex-client
./scripts/user-management.sh show-rbac
./scripts/user-management.sh test-login
```
Roles: admin | developers | viewers
Tenants: team-a | team-b (extend as needed)

## Onboard Example
```bash
export GITHUB_TOKEN=ghp_your_pat
./scripts/user-management.sh onboard alice team-a developers
# User logs in to ArgoCD via Dex; verify groups:
argocd account get-user-info | grep team-a-developers
```

## Offboard Example
```bash
./scripts/user-management.sh offboard alice team-a developers
```

## Rotate ArgoCD Admin Password
```bash
./scripts/user-management.sh rotate-argocd-admin
kubectl -n argocd rollout restart deployment argocd-server
```
ExternalSecret will sync new password from Vault (kv/argocd/admin).

## Rotate Dex Static Client Secret
```bash
./scripts/user-management.sh rotate-dex-client
kubectl -n argocd rollout restart deployment argocd-server
```
Ensure Vault path kv/argocd/dex also contains:
- dex.github.clientId
- dex.github.clientSecret

## Manual Vault Secret Setup (GitHub OAuth)
```bash
kubectl exec -n vault vault-dev-0 -- vault kv put kv/argocd/dex \
  dex.github.clientId=XXXX \
  dex.github.clientSecret=YYYY \
  dex.github.staticClientSecret=$(openssl rand -hex 32)
```

## Testing Tenant Isolation
1. Login as team-a user -> Only team-a apps visible; sync permitted.
2. Attempt to view team-b apps (should not appear).
3. Use argocd CLI:
```bash
argocd app list | grep team-a
argocd app list | grep team-b # should be empty if user not in team-b groups
```
4. RBAC policy review:
```bash
./scripts/user-management.sh show-rbac
```

## Adding a New Tenant (Summary)
1. Add teams in GitHub: team-c-admins/developers/viewers
2. Extend Dex config (config.yaml) org teams list or allow all teams.
3. Create tenants/team-c/tenant.values.yaml with groups.
4. Add AppProject (argocd/projects/per-tenant-projects.yaml).
5. Run Vault multitenancy script.
6. Onboard users with script.

## Troubleshooting
- Missing groups after login: Ensure team slug matches Dex config and user is added to GitHub team.
- 403 on sync: Verify user is developer/admin group (policy.csv).
- Secret access errors: Check Vault role (auth/kubernetes/role/<tenant>) and SecretStore in tenant namespace.

## Security Notes
- Always rotate static client secret on compromise.
- Restrict GITHUB_TOKEN usage to CI or admin workstation.
- Consider audit of team membership regularly.
