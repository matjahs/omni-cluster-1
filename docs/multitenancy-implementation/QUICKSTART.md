# Multi-tenancy Quick Start Guide

This guide will help you implement multi-tenant authentication in 30 minutes.

## Prerequisites

- [x] Kubernetes cluster running
- [x] ArgoCD deployed
- [x] Vault deployed and unsealed
- [x] External Secrets Operator configured
- [ ] SSO provider (GitHub/GitLab/Keycloak) or use local users for testing

## Option 1: Quick Setup with Local Users (Testing)

Perfect for development and testing. No external SSO required.

### Step 1: Create AppProjects

```bash
# Apply per-tenant AppProjects
kubectl apply -f docs/multitenancy-implementation/argocd-projects/team-a-project.yaml
kubectl apply -f docs/multitenancy-implementation/argocd-projects/team-b-project.yaml

# Verify
kubectl get appproject -n argocd
```

### Step 2: Configure ArgoCD RBAC

```bash
# Apply RBAC configuration
kubectl apply -f docs/multitenancy-implementation/argocd-rbac/rbac-cm.yaml

# Restart ArgoCD components to pick up changes
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Step 3: Create Local Test Users

```bash
# Port-forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get admin password
ADMIN_PASS=$(kubectl get secret argocd-secret -n argocd -o jsonpath='{.data.admin\.password}' | base64 -d)

# Login as admin
argocd login localhost:8080 --username admin --password "$ADMIN_PASS" --insecure

# Create team-a admin user
argocd account update-password \
  --account team-a-admin \
  --current-password "$ADMIN_PASS" \
  --new-password 'TeamA-Admin-123!' \
  --server localhost:8080 \
  --insecure

# Create team-b admin user
argocd account update-password \
  --account team-b-admin \
  --current-password "$ADMIN_PASS" \
  --new-password 'TeamB-Admin-123!' \
  --server localhost:8080 \
  --insecure

# Enable login for these accounts
kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  accounts.team-a-admin: "apiKey, login"
  accounts.team-b-admin: "apiKey, login"
'

# Restart ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

### Step 4: Grant Roles to Local Users

```bash
# Update RBAC to grant roles to local users
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
data:
  policy.csv: |
    # Platform admin
    g, admin, role:admin

    # Local users for testing
    g, team-a-admin, role:team-a-admin
    g, team-b-admin, role:team-b-admin

    # Team A roles
    p, role:team-a-admin, applications, *, team-a/*, allow
    p, role:team-a-admin, repositories, get, *, allow
    p, role:team-a-admin, projects, get, team-a, allow
    p, role:team-a-admin, logs, get, team-a/*, allow

    # Team B roles
    p, role:team-b-admin, applications, *, team-b/*, allow
    p, role:team-b-admin, repositories, get, *, allow
    p, role:team-b-admin, projects, get, team-b, allow
    p, role:team-b-admin, logs, get, team-b/*, allow
'

kubectl rollout restart deployment argocd-server -n argocd
```

### Step 5: Test Login

```bash
# Wait for rollout to complete
kubectl rollout status deployment argocd-server -n argocd

# Test team-a login
argocd login localhost:8080 \
  --username team-a-admin \
  --password 'TeamA-Admin-123!' \
  --insecure

# List apps (should only see team-a apps)
argocd app list

# Test team-b login
argocd login localhost:8080 \
  --username team-b-admin \
  --password 'TeamB-Admin-123!' \
  --insecure

# List apps (should only see team-b apps)
argocd app list
```

### Step 6: Setup Vault Multi-tenancy

```bash
# Run the Vault setup script
./docs/multitenancy-implementation/vault-policies/setup-vault-multitenancy.sh

# Create test secrets
kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-a/demo \
  db_password="team-a-secret-password" \
  api_key="team-a-api-key"

kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-b/demo \
  db_password="team-b-secret-password" \
  api_key="team-b-api-key"
```

### Step 7: Deploy Kubernetes RBAC (Optional)

For kubectl access control:

```bash
# Apply team-a RBAC
kubectl apply -f docs/multitenancy-implementation/tenant-rbac/team-a-rbac.yaml

# Note: This requires Kubernetes API server to be configured with OIDC
# or you can use service accounts for programmatic access
```

---

## Option 2: Production Setup with SSO

### Step 1: Choose SSO Provider

#### GitHub OAuth

1. Go to https://github.com/settings/developers
2. Click "New OAuth App"
3. Set:
   - **Application name**: ArgoCD Production
   - **Homepage URL**: https://argocd.lab.mxe11.nl
   - **Authorization callback URL**: https://argocd.lab.mxe11.nl/auth/callback
4. Note the **Client ID** and **Client Secret**

#### Generic OIDC (Keycloak/Okta/Auth0)

1. Create a new OIDC client in your provider
2. Set redirect URI: https://argocd.lab.mxe11.nl/auth/callback
3. Enable group claims in ID token
4. Note the **Client ID**, **Client Secret**, and **Issuer URL**

### Step 2: Store SSO Credentials in Vault

#### For GitHub:

```bash
kubectl exec -n vault vault-dev-0 -- vault kv put kv/argocd/oidc-github \
  clientId="YOUR_GITHUB_CLIENT_ID" \
  clientSecret="YOUR_GITHUB_CLIENT_SECRET"
```

#### For Generic OIDC:

```bash
kubectl exec -n vault vault-dev-0 -- vault kv put kv/argocd/oidc-generic \
  clientId="YOUR_OIDC_CLIENT_ID" \
  clientSecret="YOUR_OIDC_CLIENT_SECRET"
```

### Step 3: Apply SSO Configuration

#### For GitHub:

```bash
kubectl apply -f docs/multitenancy-implementation/argocd-rbac/config-sso-github.yaml
```

#### For Generic OIDC:

```bash
# Edit the issuer URL first!
vim docs/multitenancy-implementation/argocd-rbac/config-sso-generic-oidc.yaml

kubectl apply -f docs/multitenancy-implementation/argocd-rbac/config-sso-generic-oidc.yaml
```

### Step 4: Apply AppProjects and RBAC

```bash
# Apply AppProjects
kubectl apply -f docs/multitenancy-implementation/argocd-projects/

# Apply RBAC
kubectl apply -f docs/multitenancy-implementation/argocd-rbac/rbac-cm.yaml

# Restart ArgoCD
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Step 5: Configure Groups in SSO Provider

Create these groups in your SSO provider and assign users:

- `platform-admins` - Full cluster access
- `team-a-admins` - Admin access to team-a
- `team-a-developers` - Developer access to team-a
- `team-a-viewers` - Read-only access to team-a
- `team-b-admins` - Admin access to team-b
- `team-b-developers` - Developer access to team-b
- `team-b-viewers` - Read-only access to team-b

### Step 6: Test SSO Login

1. Open https://argocd.lab.mxe11.nl
2. Click "Login via GitHub" (or your SSO provider)
3. Authenticate
4. Verify you only see applications from your team

---

## Verification Checklist

### ArgoCD Multi-tenancy

- [ ] AppProjects exist for each tenant
  ```bash
  kubectl get appproject -n argocd
  ```

- [ ] RBAC policies configured
  ```bash
  kubectl get cm argocd-rbac-cm -n argocd -o yaml
  ```

- [ ] Users can login and see only their apps
  ```bash
  argocd app list
  ```

### Vault Multi-tenancy

- [ ] Vault policies exist for each tenant
  ```bash
  kubectl exec -n vault vault-dev-0 -- vault policy list
  ```

- [ ] Kubernetes auth roles configured
  ```bash
  kubectl exec -n vault vault-dev-0 -- vault list auth/kubernetes/role
  ```

- [ ] Tenants can access only their secrets
  ```bash
  # Test team-a access (should succeed)
  kubectl exec -n vault vault-dev-0 -- vault kv get kv/team-a/demo

  # Test team-a accessing team-b (should fail)
  kubectl exec -n vault vault-dev-0 -- vault kv get kv/team-b/demo
  ```

### Kubernetes RBAC

- [ ] Roles and RoleBindings exist
  ```bash
  kubectl get role,rolebinding -n team-a
  ```

- [ ] Service accounts created
  ```bash
  kubectl get sa -n team-a
  ```

---

## Troubleshooting

### SSO Login Not Working

1. Check ArgoCD server logs:
   ```bash
   kubectl logs -n argocd deployment/argocd-server --tail=50
   ```

2. Verify OIDC configuration:
   ```bash
   kubectl get cm argocd-cm -n argocd -o yaml | grep -A 20 oidc
   ```

3. Check callback URL matches exactly in SSO provider

### Users Not Seeing Applications

1. Check RBAC configuration:
   ```bash
   kubectl get cm argocd-rbac-cm -n argocd -o yaml
   ```

2. Verify user's groups:
   ```bash
   argocd account get-user-info
   ```

3. Check AppProject permissions:
   ```bash
   kubectl get appproject team-a -n argocd -o yaml
   ```

### Vault Access Denied

1. Check Vault policy:
   ```bash
   kubectl exec -n vault vault-dev-0 -- vault policy read team-a-policy
   ```

2. Verify Kubernetes auth role:
   ```bash
   kubectl exec -n vault vault-dev-0 -- vault read auth/kubernetes/role/team-a
   ```

3. Check service account token:
   ```bash
   kubectl get sa -n team-a
   ```

---

## Next Steps

1. **Enable Audit Logging**
   - ArgoCD audit logs
   - Vault audit logs
   - Kubernetes audit logs

2. **Setup Monitoring**
   - Track login attempts
   - Monitor unauthorized access attempts
   - Alert on RBAC violations

3. **Document Onboarding Process**
   - New tenant creation
   - User provisioning
   - Access request workflow

4. **Regular Security Reviews**
   - Review group memberships
   - Audit access logs
   - Update policies as needed
