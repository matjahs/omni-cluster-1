# Multi-Tenancy Implementation Proposal

## Overview

This proposal outlines a comprehensive multi-tenant authentication and authorization strategy for the Kubernetes cluster, enabling users to log in as specific tenants (e.g., `tenant-a`, `tenant-b`) with appropriate access controls.

## Architecture

### 1. Three-Layer Security Model

```
┌─────────────────────────────────────────────────────────┐
│                   ArgoCD Layer                          │
│  - SSO/OIDC Authentication                              │
│  - AppProjects per tenant                               │
│  - RBAC policies                                        │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                 Kubernetes Layer                        │
│  - Namespace isolation (team-a, team-b)                 │
│  - RBAC (Roles, RoleBindings)                           │
│  - NetworkPolicies                                      │
│  - ResourceQuotas                                       │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                    Vault Layer                          │
│  - Per-tenant secret paths (kv/team-a/*, kv/team-b/*)   │
│  - Vault policies per tenant                            │
│  - Kubernetes auth roles per tenant                     │
└─────────────────────────────────────────────────────────┘
```

## Implementation Options

### Option 1: SSO with OIDC (Recommended for Production)

**Pros:**
- Enterprise-grade authentication
- Single sign-on experience
- Group/role mapping from identity provider
- Audit trail through IdP

**Cons:**
- Requires external identity provider (GitHub, GitLab, Keycloak, etc.)
- More complex initial setup

### Option 2: Local Users (Good for Testing/Development)

**Pros:**
- Simple to set up
- No external dependencies
- Good for demos and development

**Cons:**
- Manual user management
- No SSO
- Password management overhead

### Option 3: Hybrid Approach (Recommended)

**Best of both worlds:**
- SSO for human users
- Local accounts for service accounts and emergency access
- Allows gradual migration

## Detailed Implementation Plan

---

## Phase 1: ArgoCD Multi-tenant AppProjects

### Current State
- Single `tenants` AppProject for all tenants
- No RBAC configured

### Proposed Changes

Create individual AppProjects per tenant:

```yaml
# argocd/projects/team-a-project.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: AppProject for team-a tenant

  # Source repositories this project can deploy from
  sourceRepos:
    - 'https://github.com/matjahs/omni-cluster-1.git'
    - 'https://charts.bitnami.com/bitnami'
    - 'https://*.github.io/*'  # Public Helm repos

  # Destination namespaces and clusters
  destinations:
    - namespace: 'team-a'
      server: https://kubernetes.default.svc

  # Cluster-scoped resources (none for tenants)
  clusterResourceWhitelist: []

  # Namespace-scoped resources (allow all)
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  # RBAC roles for this project
  roles:
    - name: admin
      description: Admin role for team-a
      policies:
        - p, proj:team-a:admin, applications, *, team-a/*, allow
        - p, proj:team-a:admin, repositories, *, team-a/*, allow
        - p, proj:team-a:admin, clusters, get, team-a/*, allow
      groups:
        - team-a-admins
        - platform-admins

    - name: developer
      description: Developer role for team-a (read-only + sync)
      policies:
        - p, proj:team-a:developer, applications, get, team-a/*, allow
        - p, proj:team-a:developer, applications, sync, team-a/*, allow
        - p, proj:team-a:developer, repositories, get, team-a/*, allow
      groups:
        - team-a-developers

    - name: viewer
      description: View-only role for team-a
      policies:
        - p, proj:team-a:viewer, applications, get, team-a/*, allow
      groups:
        - team-a-viewers

  orphanedResources:
    warn: true
```

---

## Phase 2: ArgoCD SSO Configuration

### Option A: GitHub OIDC

```yaml
# apps/argocd/argocd/config-sso.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com

  # OIDC configuration
  oidc.config: |
    name: GitHub
    issuer: https://github.com
    clientID: $oidc.github.clientId
    clientSecret: $oidc.github.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
    requestedIDTokenClaims:
      groups:
        essential: true

  # Admin users
  admin.enabled: "true"

  # Dex disabled (using external OIDC)
  dex.config: ""
```

Store GitHub OAuth credentials in Vault:

```bash
vault kv put kv/argocd/oidc-github \
  clientId="your-github-oauth-app-client-id" \
  clientSecret="your-github-oauth-app-client-secret"
```

### Option B: Generic OIDC (Keycloak, Okta, Auth0, etc.)

```yaml
data:
  oidc.config: |
    name: Corporate SSO
    issuer: https://keycloak.example.com/realms/kubernetes
    clientID: $oidc.keycloak.clientId
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
    # Map OIDC groups to ArgoCD groups
    scopes: ["openid", "profile", "email", "groups"]
```

---

## Phase 3: ArgoCD RBAC Configuration

```yaml
# apps/argocd/argocd/rbac-cm.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # Policy rules
  policy.csv: |
    # Platform admins have full access
    g, platform-admins, role:admin

    # Team A permissions
    g, team-a-admins, role:team-a-admin
    g, team-a-developers, role:team-a-developer
    g, team-a-viewers, role:team-a-viewer

    # Team B permissions
    g, team-b-admins, role:team-b-admin
    g, team-b-developers, role:team-b-developer
    g, team-b-viewers, role:team-b-viewer

    # Custom roles
    p, role:team-a-admin, applications, *, team-a/*, allow
    p, role:team-a-admin, repositories, *, *, allow
    p, role:team-a-admin, projects, get, team-a, allow

    p, role:team-a-developer, applications, get, team-a/*, allow
    p, role:team-a-developer, applications, sync, team-a/*, allow
    p, role:team-a-developer, applications, override, team-a/*, allow
    p, role:team-a-developer, repositories, get, *, allow
    p, role:team-a-developer, projects, get, team-a, allow

    p, role:team-a-viewer, applications, get, team-a/*, allow
    p, role:team-a-viewer, projects, get, team-a, allow

    # Repeat for team-b
    p, role:team-b-admin, applications, *, team-b/*, allow
    p, role:team-b-admin, repositories, *, *, allow
    p, role:team-b-admin, projects, get, team-b, allow

    p, role:team-b-developer, applications, get, team-b/*, allow
    p, role:team-b-developer, applications, sync, team-b/*, allow
    p, role:team-b-developer, repositories, get, *, allow
    p, role:team-b-developer, projects, get, team-b, allow

    p, role:team-b-viewer, applications, get, team-b/*, allow
    p, role:team-b-viewer, projects, get, team-b, allow

  # Default role for authenticated users
  policy.default: role:readonly

  # OIDC group claims mapping
  scopes: '[groups, email]'
```

---

## Phase 4: Kubernetes RBAC per Tenant

### Namespace-level RBAC

```yaml
# tenants/team-a/rbac.yaml
---
# Admin role - full access to namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-admin
  namespace: team-a
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-admin-binding
  namespace: team-a
subjects:
  # OIDC users (if using OIDC with Kubernetes)
  - kind: Group
    name: team-a-admins
    apiGroup: rbac.authorization.k8s.io
  # Service account for CI/CD
  - kind: ServiceAccount
    name: team-a-ci
    namespace: team-a
roleRef:
  kind: Role
  name: team-a-admin
  apiGroup: rbac.authorization.k8s.io
---
# Developer role - read + deploy
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-developer
  namespace: team-a
rules:
  - apiGroups: ["", "apps", "batch", "networking.k8s.io"]
    resources: ["*"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods/log", "pods/exec"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-developer-binding
  namespace: team-a
subjects:
  - kind: Group
    name: team-a-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-developer
  apiGroup: rbac.authorization.k8s.io
---
# Viewer role - read-only
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-viewer
  namespace: team-a
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-viewer-binding
  namespace: team-a
subjects:
  - kind: Group
    name: team-a-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-viewer
  apiGroup: rbac.authorization.k8s.io
---
# Service account for CI/CD pipelines
apiVersion: v1
kind: ServiceAccount
metadata:
  name: team-a-ci
  namespace: team-a
```

---

## Phase 5: Vault Multi-tenancy

### Vault Policies per Tenant

```bash
# Create policy for team-a
kubectl exec -n vault vault-dev-0 -- vault policy write team-a-policy - <<EOF
# Read/write access to team-a secrets
path "kv/data/team-a/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/team-a/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to shared secrets
path "kv/data/shared/*" {
  capabilities = ["read", "list"]
}
EOF

# Create Kubernetes auth role for team-a
kubectl exec -n vault vault-dev-0 -- vault write auth/kubernetes/role/team-a \
  bound_service_account_names=external-secrets,team-a-ci \
  bound_service_account_namespaces=team-a \
  policies=team-a-policy \
  ttl=24h
```

### Per-tenant ClusterSecretStore or SecretStore

```yaml
# tenants/team-a/vault-secretstore.yaml
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-team-a
  namespace: team-a
spec:
  provider:
    vault:
      server: "http://vault-dev.vault.svc:8200"
      path: "kv"
      version: "v2"
      auth:
        kubernetes:
          mountPath: kubernetes
          role: team-a  # Vault role for team-a
          serviceAccountRef:
            name: external-secrets  # Or team-a-specific SA
```

---

## Phase 6: Testing with Local Users (Optional)

For development/testing without SSO:

```bash
# Create local user for team-a-admin
argocd account update-password \
  --account team-a-admin \
  --new-password 'SecurePassword123!'

# Grant role
kubectl patch configmap argocd-cm -n argocd --type merge -p '
data:
  accounts.team-a-admin: apiKey, login
'

# Add to RBAC
kubectl patch configmap argocd-rbac-cm -n argocd --type merge -p '
data:
  policy.csv: |
    g, team-a-admin, role:team-a-admin
    # ... rest of policies
'
```

---

## Implementation Roadmap

### Week 1: Planning & Preparation
- [ ] Choose SSO provider (GitHub/GitLab/Keycloak/etc.)
- [ ] Register OAuth application with provider
- [ ] Document group/role mappings
- [ ] Create test users in each group

### Week 2: ArgoCD Configuration
- [ ] Create per-tenant AppProjects (team-a, team-b)
- [ ] Configure SSO in ArgoCD
- [ ] Implement RBAC policies
- [ ] Test SSO login flow

### Week 3: Kubernetes RBAC
- [ ] Create Roles and RoleBindings per tenant
- [ ] Create service accounts for CI/CD
- [ ] Test kubectl access with different roles

### Week 4: Vault Integration
- [ ] Create Vault policies per tenant
- [ ] Create Kubernetes auth roles
- [ ] Set up per-tenant SecretStores
- [ ] Migrate secrets to tenant-specific paths

### Week 5: Testing & Documentation
- [ ] End-to-end testing with each tenant
- [ ] Load testing and security audit
- [ ] Create runbooks for common operations
- [ ] Train users on new authentication

---

## Security Considerations

1. **Least Privilege**: Users should only have access to their tenant's resources
2. **Network Isolation**: Use NetworkPolicies to prevent cross-tenant traffic
3. **Secret Isolation**: Vault policies ensure tenants can't access each other's secrets
4. **Audit Logging**: Enable audit logs in ArgoCD and Kubernetes
5. **MFA**: Enforce MFA at the SSO provider level
6. **Token Expiry**: Configure short-lived tokens with refresh

---

## Example User Workflows

### Tenant Admin Workflow
1. User logs into ArgoCD via SSO
2. SSO provider authenticates and returns group membership (`team-a-admins`)
3. ArgoCD RBAC maps group to `role:team-a-admin`
4. User sees only `team-a` project and applications
5. User can create/modify/delete applications in `team-a` namespace

### Developer Workflow
1. User logs in (member of `team-a-developers` group)
2. Can view applications and trigger syncs
3. Cannot create new applications or modify AppProject
4. Can view logs and exec into pods via kubectl (if K8s RBAC is configured)

### CI/CD Workflow
1. CI pipeline uses `team-a-ci` service account
2. Service account has Kubernetes RBAC to deploy to `team-a` namespace
3. Can authenticate to Vault to retrieve secrets
4. Cannot access other tenants' resources

---

## Monitoring & Alerting

```yaml
# Prometheus alerts for multi-tenancy violations
- alert: UnauthorizedNamespaceAccess
  expr: |
    rate(apiserver_audit_event_total{
      verb=~"create|update|patch|delete",
      objectRef_namespace!~"team-a",
      user_username=~".*team-a.*"
    }[5m]) > 0
  annotations:
    summary: "User from team-a accessed unauthorized namespace"
```

---

## Migration Plan for Existing Resources

1. **Backup current state**
   ```bash
   kubectl get all -n team-a -o yaml > team-a-backup.yaml
   ```

2. **Update ApplicationSets to use new projects**
   ```yaml
   spec:
     template:
       spec:
         project: team-a  # Changed from 'tenants'
   ```

3. **Gradually migrate users**
   - Start with test users
   - Run SSO and local users in parallel
   - Monitor for issues
   - Full cutover after validation

---

## Cost & Maintenance

### One-time Setup Cost
- SSO configuration: 2-4 hours
- RBAC policy development: 4-8 hours
- Testing and validation: 8-16 hours
- **Total: ~2-3 days**

### Ongoing Maintenance
- User onboarding: 15 min per user (automated via SSO groups)
- New tenant setup: 1-2 hours (can be templated)
- Policy updates: As needed

---

## Alternative Approaches

### Virtual Clusters (vCluster)
- **Pros**: Complete isolation, each tenant gets "their own cluster"
- **Cons**: Higher resource overhead, more complex
- **Use case**: When tenants need cluster-admin privileges

### Hierarchical Namespaces (HNC)
- **Pros**: Namespace inheritance, easier policy management
- **Cons**: Additional operator to maintain
- **Use case**: Large organizations with deep hierarchy

### Capsule
- **Pros**: Purpose-built multi-tenancy operator
- **Cons**: Another dependency
- **Use case**: Very large number of tenants (100+)

---

## Recommendation

**Recommended approach: Hybrid ArgoCD + Kubernetes RBAC**

This gives you:
- ✅ Simple to implement and understand
- ✅ Leverages existing ArgoCD deployment
- ✅ Clear separation of concerns
- ✅ Easy to audit and troubleshoot
- ✅ Scalable to 10-50 tenants
- ✅ No additional operators required

Start with **OIDC SSO + per-tenant AppProjects + RBAC policies**.
