# Multi-Tenancy: What's Already There vs What's New

## ✅ What You Already Have (Excellent Foundation!)

### 1. Tenant Infrastructure (`helm/tenant-baseline/`)
- ✅ RBAC with admin role
- ✅ ResourceQuotas per tenant
- ✅ LimitRanges
- ✅ NetworkPolicies (default deny + same namespace allow)
- ✅ Pod Security Standards
- ✅ ServiceAccount support

### 2. Automated Tenant Discovery (`argocd/apps/tenant-appset.yaml`)
- ✅ ApplicationSet automatically discovers `tenants/*/`
- ✅ Deploys tenant-baseline chart with per-tenant values
- ✅ Deploys optional tenant apps from `tenants/{name}/app/`
- ✅ Automated sync enabled

### 3. Existing Tenants
- ✅ `team-a` configured with apps
- ✅ `team-b` configured with apps
- ✅ Both already reference OIDC groups in values

### 4. Current State
```bash
$ kubectl get applications -n argocd | grep team
team-a    Unknown    Healthy
team-b    Unknown    Healthy

$ ls tenants/
team-a/  team-b/
```

---

## 🎯 What We're Adding (Authentication & Authorization)

### 1. ArgoCD Layer - Who Can See What

**New Files:**
- `argocd/projects/per-tenant-projects.yaml` - One AppProject per tenant
- `apps/argocd/argocd/config-sso.yaml` - GitHub/OIDC login
- `apps/argocd/argocd/rbac-cm.yaml` - Map groups to permissions

**Changes:**
- `argocd/apps/tenant-appset.yaml` - Use per-tenant projects instead of shared "tenants" project
- `apps/argocd/argocd/kustomization.yaml` - Include new patches

**Result:**
- Users login via GitHub/OIDC
- See only their team's applications in ArgoCD UI
- Can only deploy to their team's namespace

### 2. Kubernetes Layer - Enhanced RBAC

**Changes to Existing Chart:**
- `helm/tenant-baseline/values.yaml` - Add `developerGroups` and `viewerGroups`
- `helm/tenant-baseline/templates/rbac.yaml` - Add developer and viewer roles
- `helm/tenant-baseline/templates/vault-secretstore.yaml` - New file for per-tenant Vault access

**Update Tenant Values:**
- `tenants/team-a/tenant.values.yaml` - Add developer/viewer groups
- `tenants/team-b/tenant.values.yaml` - Add developer/viewer groups

**Result:**
- 3 roles per tenant: admin, developer, viewer
- Granular kubectl access control
- ServiceAccounts for CI/CD

### 3. Vault Layer - Secret Isolation

**New Files:**
- `scripts/setup-vault-multitenancy.sh` - Auto-setup Vault policies and roles

**Result:**
- Each tenant has isolated secret path: `kv/team-a/*`, `kv/team-b/*`
- Automatic SecretStore creation per tenant
- Cross-tenant access denied

---

## 📊 Architecture Comparison

### Before (Current State)
```
User → ArgoCD (no auth) → Kubernetes
  ├─ All users see all applications
  ├─ Single "tenants" AppProject
  └─ Kubernetes RBAC: admin role only

Vault: Single external-secrets role for all
```

### After (Multi-tenant)
```
User → GitHub/OIDC → ArgoCD RBAC → Per-tenant AppProject → Kubernetes
  ├─ team-a-admin sees only team-a apps
  ├─ team-a-developer can sync but not create apps
  └─ team-a-viewer read-only

Kubernetes RBAC:
  ├─ team-a-admin: full namespace access
  ├─ team-a-developer: deploy + debug
  └─ team-a-viewer: read-only

Vault:
  ├─ team-a can access kv/team-a/* only
  └─ team-b can access kv/team-b/* only
```

---

## 🔧 Implementation Plan

### Phase 1: Enhance Tenant Baseline Chart (10 min)

Add multi-role support to your existing chart:

```bash
# Edit these files (examples provided in docs/MULTITENANCY-INTEGRATED.md):
helm/tenant-baseline/values.yaml                 # Add developerGroups, viewerGroups, vault
helm/tenant-baseline/templates/rbac.yaml         # Add developer and viewer roles
helm/tenant-baseline/templates/vault-secretstore.yaml  # NEW file

# Update tenant values:
tenants/team-a/tenant.values.yaml
tenants/team-b/tenant.values.yaml

# Commit
git add helm/ tenants/
git commit -m "feat: add multi-role RBAC to tenant-baseline"
```

### Phase 2: Create Per-Tenant AppProjects (5 min)

```bash
# Apply new projects
kubectl apply -f argocd/projects/per-tenant-projects.yaml

# Verify
kubectl get appproject -n argocd
# Should show: default, team-a, team-b, tenants
```

### Phase 3: Update Tenant ApplicationSet (5 min)

```bash
# Edit argocd/apps/tenant-appset.yaml
# Change line 21: project: '{{path.basename}}'  # was: project: tenants

# Apply
kubectl apply -f argocd/apps/tenant-appset.yaml
```

### Phase 4: Configure ArgoCD SSO (15 min)

```bash
# 1. Create GitHub OAuth App
#    - Go to: https://github.com/settings/developers
#    - New OAuth App
#    - Callback URL: https://argocd.lab.mxe11.nl/auth/callback
#    - Note the Client ID and Client Secret

# 2. Store in Vault
kubectl exec -n vault vault-dev-0 -- vault kv put kv/argocd/oidc-github \
  clientId="YOUR_GITHUB_CLIENT_ID" \
  clientSecret="YOUR_GITHUB_CLIENT_SECRET"

# 3. Add new patches to kustomization
# Edit apps/argocd/argocd/kustomization.yaml
# Add to patches:
#   - path: config-sso.yaml
#   - path: rbac-cm.yaml

# 4. Apply
kustomize build apps/argocd/argocd | kubectl apply -f -

# 5. Restart ArgoCD
kubectl rollout restart deployment argocd-server -n argocd
```

### Phase 5: Setup Vault Multi-tenancy (5 min)

```bash
# Run the script (auto-discovers tenants)
./scripts/setup-vault-multitenancy.sh

# Create test secrets
kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-a/demo password="team-a-secret"
kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-b/demo password="team-b-secret"
```

### Phase 6: Verify (5 min)

```bash
# Check applications recreated with new project
kubectl get applications -n argocd

# Check RBAC roles
kubectl get roles -n team-a
# Should see: team-a-admin, team-a-developer, team-a-viewer

# Check Vault SecretStore
kubectl get secretstore -n team-a
# Should see: vault-team-a

# Test ArgoCD UI
# 1. Open https://argocd.lab.mxe11.nl
# 2. Click "Login via GitHub"
# 3. Should only see team-a or team-b apps based on your GitHub org membership
```

---

## 🎭 User Roles Explained

### Platform Admin
- **Group:** `platform-admins`
- **ArgoCD:** Full access to all applications and projects
- **Kubernetes:** Can access all namespaces
- **Vault:** Admin access

### Team Admin (e.g., team-a-admins)
- **Group:** `team-a-admins`
- **ArgoCD:** Full control of team-a applications
  - Create/update/delete applications
  - Trigger syncs
  - View logs
- **Kubernetes:** Full access to team-a namespace
- **Vault:** Read/write kv/team-a/*

### Team Developer (e.g., team-a-developers)
- **Group:** `team-a-developers`
- **ArgoCD:** Limited control
  - View applications
  - Trigger syncs
  - View logs
  - Cannot create/delete apps
- **Kubernetes:** Can deploy, update, exec into pods
- **Vault:** Read/write kv/team-a/*

### Team Viewer (e.g., team-a-viewers)
- **Group:** `team-a-viewers`
- **ArgoCD:** Read-only
  - View applications
  - Cannot sync or modify
- **Kubernetes:** Read-only access to team-a namespace
- **Vault:** Read-only kv/team-a/*

---

## 🆕 Adding a New Tenant (2 min)

```bash
# 1. Create tenant directory and values
mkdir -p tenants/team-c/app
cat > tenants/team-c/tenant.values.yaml <<EOF
---
tenantName: team-c
rbac:
  adminGroups: [team-c-admins, platform-admins]
  developerGroups: [team-c-developers]
  viewerGroups: [team-c-viewers]
vault:
  enabled: true
EOF

# 2. Add AppProject (copy team-a section in argocd/projects/per-tenant-projects.yaml)

# 3. Add RBAC rules (copy team-a section in apps/argocd/argocd/rbac-cm.yaml)

# 4. Run Vault setup
./scripts/setup-vault-multitenancy.sh

# 5. ApplicationSet auto-discovers and deploys!
# Wait 1-2 minutes or:
argocd app sync team-c
```

---

## 📝 Files Changed/Added Summary

### New Files
```
argocd/projects/per-tenant-projects.yaml
apps/argocd/argocd/config-sso.yaml
apps/argocd/argocd/rbac-cm.yaml
helm/tenant-baseline/templates/vault-secretstore.yaml
scripts/setup-vault-multitenancy.sh
docs/MULTITENANCY-INTEGRATED.md
docs/MULTITENANCY-SUMMARY.md
```

### Modified Files
```
helm/tenant-baseline/values.yaml                 # Add new role groups
helm/tenant-baseline/templates/rbac.yaml         # Add developer/viewer roles
tenants/team-a/tenant.values.yaml                # Add role groups
tenants/team-b/tenant.values.yaml                # Add role groups
argocd/apps/tenant-appset.yaml                   # Use per-tenant projects
apps/argocd/argocd/kustomization.yaml            # Include new patches
```

---

## 🔒 Security Features

1. **SSO Authentication**
   - GitHub OAuth (or any OIDC provider)
   - MFA enforced at provider level
   - No password management

2. **Authorization Layers**
   - ArgoCD RBAC (GitOps control)
   - Kubernetes RBAC (runtime access)
   - Vault policies (secret isolation)

3. **Namespace Isolation**
   - NetworkPolicies block cross-namespace traffic
   - ResourceQuotas prevent resource exhaustion
   - Pod Security Standards enforced

4. **Audit Trail**
   - ArgoCD tracks all GitOps operations
   - Kubernetes audit logs
   - Vault audit logs

---

## 📚 Documentation

- **Full Integration Guide:** `docs/MULTITENANCY-INTEGRATED.md`
- **This Summary:** `docs/MULTITENANCY-SUMMARY.md`
- **Original Proposal:** `docs/multitenancy-proposal.md`
- **Implementation Examples:** `docs/multitenancy-implementation/`

---

## 🎯 Next Steps

1. **Review the changes:**
   ```bash
   cat docs/MULTITENANCY-INTEGRATED.md
   ```

2. **Test in development:**
   - Start with Phase 1 (enhance tenant-baseline)
   - Deploy to a test tenant first
   - Verify RBAC works as expected

3. **Setup SSO:**
   - Create GitHub OAuth app (or configure your OIDC provider)
   - Test login flow
   - Verify group mappings

4. **Roll out to production:**
   - Commit all changes
   - Sync applications
   - Monitor for issues

5. **Train users:**
   - Document login process
   - Explain role differences
   - Provide examples

---

## ❓ FAQ

**Q: Will this break my existing tenants?**
A: No! The changes are additive. Existing admin RBAC continues to work. New roles are optional.

**Q: Do I have to use SSO?**
A: No, you can test with local users first (see docs/multitenancy-implementation/QUICKSTART.md).

**Q: What if I don't use GitHub?**
A: Use the generic OIDC config example for Keycloak, Okta, Auth0, etc.

**Q: Can I add more roles?**
A: Yes! Edit the tenant-baseline chart templates to add custom roles.

**Q: How do I remove a tenant?**
A: Delete the `tenants/{name}` directory. ApplicationSet will prune automatically.

---

## 🆘 Troubleshooting

**SSO not working:**
```bash
kubectl logs -n argocd deployment/argocd-server --tail=50 | grep -i oidc
```

**Users not seeing apps:**
```bash
# Check group membership
argocd account get-user-info

# Check RBAC config
kubectl get cm argocd-rbac-cm -n argocd -o yaml
```

**Vault access denied:**
```bash
# Check policy
kubectl exec -n vault vault-dev-0 -- vault policy read team-a-policy

# Check role
kubectl exec -n vault vault-dev-0 -- vault read auth/kubernetes/role/team-a
```
