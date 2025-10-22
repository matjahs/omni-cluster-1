# Multi-Tenancy Integration Guide

## Overview

This guide shows how to add **authentication** and **per-tenant access control** to your **existing tenant structure**.

### What You Already Have ✅

```
✅ tenant-baseline Helm chart (RBAC, quotas, network policies)
✅ Tenant ApplicationSet (auto-discovers tenants/*)
✅ team-a and team-b deployed
✅ OIDC group references in tenant.values.yaml
✅ Kubernetes RBAC with admin roles
```

### What We'll Add 🎯

```
🎯 ArgoCD SSO (GitHub/OIDC login)
🎯 Per-tenant ArgoCD AppProjects
🎯 ArgoCD RBAC (control who sees what in ArgoCD UI)
🎯 Enhanced tenant-baseline with developer/viewer roles
🎯 Vault multi-tenancy
```

---

## Architecture: How It All Works Together

```
User logs in via GitHub SSO
         ↓
ArgoCD checks group membership (team-a-admins, team-a-developers, etc.)
         ↓
ArgoCD RBAC determines what apps user can see/manage
         ↓
AppProject restricts which namespaces apps can deploy to
         ↓
tenant-baseline chart creates K8s RBAC in namespace
         ↓
User can kubectl into their namespace (if K8s API has OIDC)
         ↓
Vault policies isolate secrets per tenant
```

---

## Phase 1: Enhance tenant-baseline Chart

Add developer and viewer roles to your existing chart.

### 1.1 Update helm/tenant-baseline/values.yaml

```yaml
---
tenantName: ''  # REQUIRED per-tenant via values file
labels:
  enabled: true
  extra: {}

# ENHANCED: Support multiple role levels
rbac:
  enabled: true
  adminGroups: [tenant-admins]  # Full namespace access
  developerGroups: []           # Deploy + debug access (NEW)
  viewerGroups: []               # Read-only access (NEW)
  additionalRoleBindings: []

resourceQuota:
  enabled: true
  hard:
    requests.cpu: '2'
    requests.memory: 4Gi
    limits.cpu: '4'
    limits.memory: 8Gi
    pods: '25'
    services: '10'

limitRange:
  enabled: true
  default:
    cpu: 500m
    memory: 512Mi
  defaultRequest:
    cpu: 200m
    memory: 256Mi

networkPolicy:
  defaultDenyAll: true
  allowSameNamespace: true
  extra: []

podSecurity:
  enabled: true
  level: baseline

serviceAccount:
  enabled: false
  name: default

# NEW: Vault SecretStore configuration
vault:
  enabled: false
  secretStoreName: vault-tenant
  vaultRole: ""  # Will default to tenantName if empty

extras:
  config: {}
```

### 1.2 Update helm/tenant-baseline/templates/rbac.yaml

Replace the existing file with:

```yaml
---
{{- if .Values.rbac.enabled }}
# ============================================
# Admin Role - Full namespace access
# ============================================
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .Values.tenantName }}-admin
  namespace: {{ .Values.tenantName }}
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.tenantName }}-admin-binding
  namespace: {{ .Values.tenantName }}
subjects:
{{- range .Values.rbac.adminGroups }}
  - kind: Group
    name: {{ . | quote }}
    apiGroup: rbac.authorization.k8s.io
{{- end }}
roleRef:
  kind: Role
  name: {{ .Values.tenantName }}-admin
  apiGroup: rbac.authorization.k8s.io

{{- if .Values.rbac.developerGroups }}
---
# ============================================
# Developer Role - Deploy and debug access
# ============================================
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .Values.tenantName }}-developer
  namespace: {{ .Values.tenantName }}
rules:
  # Read/write most resources
  - apiGroups: ["", "apps", "batch", "networking.k8s.io", "autoscaling"]
    resources: ["*"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Pod logs and exec
  - apiGroups: [""]
    resources: ["pods/log", "pods/portforward"]
    verbs: ["get", "list"]

  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]

  # Cannot modify RBAC
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["*"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.tenantName }}-developer-binding
  namespace: {{ .Values.tenantName }}
subjects:
{{- range .Values.rbac.developerGroups }}
  - kind: Group
    name: {{ . | quote }}
    apiGroup: rbac.authorization.k8s.io
{{- end }}
roleRef:
  kind: Role
  name: {{ .Values.tenantName }}-developer
  apiGroup: rbac.authorization.k8s.io
{{- end }}

{{- if .Values.rbac.viewerGroups }}
---
# ============================================
# Viewer Role - Read-only access
# ============================================
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .Values.tenantName }}-viewer
  namespace: {{ .Values.tenantName }}
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]

  # Pod logs
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.tenantName }}-viewer-binding
  namespace: {{ .Values.tenantName }}
subjects:
{{- range .Values.rbac.viewerGroups }}
  - kind: Group
    name: {{ . | quote }}
    apiGroup: rbac.authorization.k8s.io
{{- end }}
roleRef:
  kind: Role
  name: {{ .Values.tenantName }}-viewer
  apiGroup: rbac.authorization.k8s.io
{{- end }}
{{- end }}
```

### 1.3 Add Vault SecretStore Template

Create `helm/tenant-baseline/templates/vault-secretstore.yaml`:

```yaml
{{- if .Values.vault.enabled }}
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: {{ .Values.vault.secretStoreName }}
  namespace: {{ .Values.tenantName }}
spec:
  provider:
    vault:
      server: "http://vault-dev.vault.svc:8200"
      path: "kv"
      version: "v2"
      auth:
        kubernetes:
          mountPath: kubernetes
          role: {{ .Values.vault.vaultRole | default .Values.tenantName }}
          serviceAccountRef:
            name: {{ .Values.serviceAccount.name | default "default" }}
{{- end }}
```

### 1.4 Update tenants/team-a/tenant.values.yaml

```yaml
---
tenantName: team-a

rbac:
  adminGroups:
    - team-a-admins
    - platform-admins
  developerGroups:
    - team-a-developers
  viewerGroups:
    - team-a-viewers

resourceQuota:
  hard:
    requests.cpu: '4'
    limits.memory: 16Gi

vault:
  enabled: true
  secretStoreName: vault-team-a
  vaultRole: team-a

extras:
  config:
    customAnnotation: team-a-value
```

### 1.5 Update tenants/team-b/tenant.values.yaml

```yaml
---
tenantName: team-b

rbac:
  adminGroups:
    - team-b-admins
    - platform-admins
  developerGroups:
    - team-b-developers
  viewerGroups:
    - team-b-viewers

resourceQuota:
  hard:
    requests.cpu: '4'
    limits.memory: 16Gi

vault:
  enabled: true
  secretStoreName: vault-team-b
  vaultRole: team-b

extras:
  config:
    customAnnotation: team-b-value
```

---

## Phase 2: Per-Tenant ArgoCD AppProjects

### 2.1 Create argocd/projects/per-tenant-projects.yaml

```yaml
---
# Platform Admins Project - unchanged
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Default project for platform admins
  sourceRepos: ['*']
  destinations:
    - namespace: '*'
      server: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'

---
# Team A Project
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: AppProject for team-a tenant
  sourceRepos:
    - 'https://github.com/matjahs/omni-cluster-1.git'
    - 'https://charts.bitnami.com/bitnami'
    - 'https://*.github.io/*'

  destinations:
    - namespace: 'team-a'
      server: https://kubernetes.default.svc

  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  # Project-level roles
  roles:
    - name: admin
      description: Admin access to team-a applications
      policies:
        - p, proj:team-a:admin, applications, *, team-a/*, allow
        - p, proj:team-a:admin, logs, get, team-a/*, allow
      groups:
        - team-a-admins
        - platform-admins

    - name: developer
      description: Developer access to team-a
      policies:
        - p, proj:team-a:developer, applications, get, team-a/*, allow
        - p, proj:team-a:developer, applications, sync, team-a/*, allow
        - p, proj:team-a:developer, logs, get, team-a/*, allow
      groups:
        - team-a-developers

    - name: viewer
      description: View-only access to team-a
      policies:
        - p, proj:team-a:viewer, applications, get, team-a/*, allow
      groups:
        - team-a-viewers

---
# Team B Project
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-b
  namespace: argocd
spec:
  description: AppProject for team-b tenant
  sourceRepos:
    - 'https://github.com/matjahs/omni-cluster-1.git'
    - 'https://charts.bitnami.com/bitnami'
    - 'https://*.github.io/*'

  destinations:
    - namespace: 'team-b'
      server: https://kubernetes.default.svc

  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  roles:
    - name: admin
      policies:
        - p, proj:team-b:admin, applications, *, team-b/*, allow
        - p, proj:team-b:admin, logs, get, team-b/*, allow
      groups:
        - team-b-admins
        - platform-admins

    - name: developer
      policies:
        - p, proj:team-b:developer, applications, get, team-b/*, allow
        - p, proj:team-b:developer, applications, sync, team-b/*, allow
        - p, proj:team-b:developer, logs, get, team-b/*, allow
      groups:
        - team-b-developers

    - name: viewer
      policies:
        - p, proj:team-b:viewer, applications, get, team-b/*, allow
      groups:
        - team-b-viewers
```

### 2.2 Update argocd/apps/tenant-appset.yaml

Change line 21 from `project: tenants` to use per-tenant projects:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenants
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/matjahs/omni-cluster-1.git
        revision: main
        directories:
          - path: tenants/*
  template:
    metadata:
      name: '{{path.basename}}'
      labels:
        tenant: '{{path.basename}}'
    spec:
      # CHANGED: Use per-tenant project instead of shared "tenants" project
      project: '{{path.basename}}'

      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      sources:
        # 1) Helm tenant baseline (local chart)
        - repoURL: https://github.com/matjahs/omni-cluster-1.git
          targetRevision: main
          path: helm/tenant-baseline
          helm:
            valueFiles:
              - $values/{{path}}/tenant.values.yaml
        # 2) Optional tenant app (Kustomize overlay)
        - repoURL: https://github.com/matjahs/omni-cluster-1.git
          targetRevision: main
          path: '{{path}}/app'
      source:
        repoURL: https://github.com/matjahs/omni-cluster-1.git
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions: [CreateNamespace=true]
```

---

## Phase 3: ArgoCD SSO and RBAC

### 3.1 Add SSO Configuration Patch

Create `apps/argocd/argocd/config-sso.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.lab.mxe11.nl
  application.resourceTrackingMethod: annotation

  # GitHub SSO
  # Prerequisites:
  # 1. Create GitHub OAuth App: https://github.com/settings/developers
  # 2. Callback URL: https://argocd.lab.mxe11.nl/auth/callback
  # 3. Store credentials in Vault: kv/argocd/oidc-github
  oidc.config: |
    name: GitHub
    issuer: https://token.actions.githubusercontent.com
    clientID: $oidc.github.clientId
    clientSecret: $oidc.github.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
    requestedIDTokenClaims:
      groups:
        essential: true

  dex.config: ""
  admin.enabled: "true"
```

### 3.2 Add RBAC Configuration Patch

Create `apps/argocd/argocd/rbac-cm.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Platform admins - full access
    g, platform-admins, role:admin

    # Team A
    g, team-a-admins, role:team-a-admin
    g, team-a-developers, role:team-a-developer
    g, team-a-viewers, role:team-a-viewer

    p, role:team-a-admin, applications, *, team-a/*, allow
    p, role:team-a-admin, repositories, get, *, allow
    p, role:team-a-admin, projects, get, team-a, allow
    p, role:team-a-admin, logs, get, team-a/*, allow

    p, role:team-a-developer, applications, get, team-a/*, allow
    p, role:team-a-developer, applications, sync, team-a/*, allow
    p, role:team-a-developer, logs, get, team-a/*, allow
    p, role:team-a-developer, projects, get, team-a, allow

    p, role:team-a-viewer, applications, get, team-a/*, allow
    p, role:team-a-viewer, projects, get, team-a, allow

    # Team B
    g, team-b-admins, role:team-b-admin
    g, team-b-developers, role:team-b-developer
    g, team-b-viewers, role:team-b-viewer

    p, role:team-b-admin, applications, *, team-b/*, allow
    p, role:team-b-admin, repositories, get, *, allow
    p, role:team-b-admin, projects, get, team-b, allow
    p, role:team-b-admin, logs, get, team-b/*, allow

    p, role:team-b-developer, applications, get, team-b/*, allow
    p, role:team-b-developer, applications, sync, team-b/*, allow
    p, role:team-b-developer, logs, get, team-b/*, allow
    p, role:team-b-developer, projects, get, team-b, allow

    p, role:team-b-viewer, applications, get, team-b/*, allow
    p, role:team-b-viewer, projects, get, team-b, allow

  policy.default: role:readonly
  scopes: '[groups, email]'
```

### 3.3 Update apps/argocd/argocd/kustomization.yaml

Add the new patches:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - namespace.yaml
  - github.com/argoproj/argo-cd/manifests/cluster-install?ref=v2.11.0
  - bootstrap-app-set.yaml
  - argocd-external-secret.yaml
patches:
  - path: config.yaml
  - path: config-cmd-params.yaml
  - path: service.yaml
  - path: config-sso.yaml      # NEW
  - path: rbac-cm.yaml         # NEW
```

---

## Phase 4: Vault Multi-tenancy

### 4.1 Run Vault Setup Script

Create `scripts/setup-vault-multitenancy.sh`:

```bash
#!/bin/bash
set -e

VAULT_POD="vault-dev-0"
VAULT_NAMESPACE="vault"

for TENANT in team-a team-b; do
  echo "Setting up Vault for ${TENANT}..."

  # Create policy
  kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy write ${TENANT}-policy - <<EOF
path "kv/data/${TENANT}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/metadata/${TENANT}/*" {
  capabilities = ["read", "list", "delete"]
}
# Deny other tenants
path "kv/data/team-*" {
  capabilities = ["deny"]
}
EOF

  # Create Kubernetes auth role
  kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/${TENANT} \
    bound_service_account_names="default,external-secrets" \
    bound_service_account_namespaces="${TENANT}" \
    policies="${TENANT}-policy" \
    ttl="24h"
done

echo "Vault multi-tenancy setup complete!"
```

```bash
chmod +x scripts/setup-vault-multitenancy.sh
./scripts/setup-vault-multitenancy.sh
```

---

## Implementation Steps

### Step 1: Enhance tenant-baseline Chart
```bash
# Update the chart files as shown in Phase 1
git add helm/tenant-baseline/
git commit -m "feat: add developer and viewer roles to tenant-baseline"
```

### Step 2: Update Tenant Values
```bash
# Update team-a and team-b values as shown
git add tenants/
git commit -m "feat: add role groups and vault config to tenants"
```

### Step 3: Create AppProjects
```bash
kubectl apply -f argocd/projects/per-tenant-projects.yaml
```

### Step 4: Update Tenant ApplicationSet
```bash
# Edit argocd/apps/tenant-appset.yaml
git add argocd/apps/tenant-appset.yaml
git commit -m "feat: use per-tenant ArgoCD projects"
kubectl apply -f argocd/apps/tenant-appset.yaml
```

### Step 5: Configure ArgoCD SSO
```bash
# 1. Create GitHub OAuth App
# 2. Store credentials in Vault
kubectl exec -n vault vault-dev-0 -- vault kv put kv/argocd/oidc-github \
  clientId="YOUR_GITHUB_CLIENT_ID" \
  clientSecret="YOUR_GITHUB_CLIENT_SECRET"

# 3. Apply ArgoCD configuration
git add apps/argocd/argocd/
git commit -m "feat: add SSO and RBAC configuration"
kustomize build apps/argocd/argocd | kubectl apply -f -

# 4. Restart ArgoCD
kubectl rollout restart deployment argocd-server -n argocd
```

### Step 6: Setup Vault Multi-tenancy
```bash
./scripts/setup-vault-multitenancy.sh
```

### Step 7: Test
```bash
# Applications should recreate with new RBAC
kubectl get applications -n argocd
kubectl get roles -n team-a
kubectl get secretstore -n team-a
```

---

## Verification

### ArgoCD UI
1. Login via GitHub
2. Verify you only see your team's applications
3. Try to create an application (should only work in your namespace)

### Kubernetes RBAC
```bash
# Check roles
kubectl get role,rolebinding -n team-a

# Test access
kubectl auth can-i create deployment -n team-a --as-group=team-a-developers
```

### Vault
```bash
# Check policies
kubectl exec -n vault vault-dev-0 -- vault policy list

# Test secret access
kubectl exec -n vault vault-dev-0 -- vault kv put kv/team-a/test key=value
```

---

## Adding a New Tenant

```bash
# 1. Create tenant directory
mkdir -p tenants/team-c/app

# 2. Create tenant values
cat > tenants/team-c/tenant.values.yaml <<EOF
---
tenantName: team-c
rbac:
  adminGroups:
    - team-c-admins
  developerGroups:
    - team-c-developers
  viewerGroups:
    - team-c-viewers
vault:
  enabled: true
EOF

# 3. Create AppProject
# (Add team-c to argocd/projects/per-tenant-projects.yaml)

# 4. Vault setup will auto-create with next run of setup script

# 5. ApplicationSet auto-discovers and deploys!
```

---

## Benefits of This Integrated Approach

✅ Builds on existing tenant-baseline chart
✅ Auto-discovery of new tenants works as before
✅ Single source of truth for tenant configuration (tenant.values.yaml)
✅ Minimal changes to existing structure
✅ Fully GitOps compliant
✅ Scales easily to many tenants
