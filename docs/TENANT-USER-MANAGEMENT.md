# Tenant User Management

This guide explains how to grant users access to tenant namespaces using Omni authentication and Kubernetes RBAC.

## Overview

**Authentication:** Users authenticate via Omni (no SSO setup required)
**Authorization:** Kubernetes RoleBindings control namespace access
**ArgoCD:** Admin-only access for platform management

## User Access Workflow

### 1. Create User in Omni

1. Log into **Omni Dashboard**
2. Navigate to **Users**
3. Click **Add User**
4. Enter user email (e.g., `alice@example.com`)
5. Assign **Role: Reader** (allows kubeconfig download)

### 2. Create Kubernetes RoleBinding

Create a RoleBinding file in the tenant's resources directory:

```bash
# Example: Grant Alice admin access to team-a namespace
cat <<EOF > tenants/team-a/resources/alice-rolebinding.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-team-a-admin
  namespace: team-a
  labels:
    app.kubernetes.io/managed-by: tenant-baseline
    tenant: team-a
subjects:
- kind: User
  name: alice@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-admin
  apiGroup: rbac.authorization.k8s.io
EOF
```

### 3. Apply RoleBinding

```bash
kubectl apply -f tenants/team-a/resources/alice-rolebinding.yaml
```

### 4. User Downloads Kubeconfig

The user can now download their kubeconfig:

**Via Omni CLI:**
```bash
omnictl kubeconfig talos-default > ~/.kube/config
export KUBECONFIG=~/.kube/config
```

**Via Omni Web UI:**
- Navigate to: **Clusters** → `talos-default`
- Click: **Download Kubeconfig**

### 5. User Verifies Access

```bash
# Should work (team-a namespace)
kubectl get pods -n team-a
kubectl create deployment nginx -n team-a --image=nginx
kubectl logs -n team-a deployment/nginx

# Should fail (no access to other namespaces)
kubectl get pods -n team-b        # Forbidden
kubectl get pods -n kube-system   # Forbidden
kubectl get nodes                 # Forbidden
```

## Available Roles

Each tenant has three pre-defined roles (created by `helm/tenant-baseline` chart):

### 1. `{tenant}-admin`
- **Full access** within tenant namespace
- Can create/delete/modify all resources
- **Use case:** Tenant owners, lead developers

### 2. `{tenant}-developer`
- **Read/write access** to common workload resources
- Can manage: pods, deployments, services, configmaps, secrets
- Can view logs and exec into pods
- **Cannot** manage RBAC resources
- **Use case:** Development team members

### 3. `{tenant}-viewer`
- **Read-only access** to all resources
- Can view resources and logs
- **Cannot** modify anything
- **Use case:** Auditors, read-only access for monitoring

## Example: Multiple Users for team-a

```bash
# Admin access
kubectl apply -f - <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-team-a-admin
  namespace: team-a
subjects:
- kind: User
  name: alice@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bob-team-a-developer
  namespace: team-a
subjects:
- kind: User
  name: bob@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: charlie-team-a-viewer
  namespace: team-a
subjects:
- kind: User
  name: charlie@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## Removing User Access

To revoke access, simply delete the RoleBinding:

```bash
kubectl delete rolebinding alice-team-a-admin -n team-a
```

The user will no longer have access to the namespace (kubeconfig will still work for authentication, but all operations will be forbidden).

## Troubleshooting

### User gets "Forbidden" errors for their namespace

1. **Check RoleBinding exists:**
   ```bash
   kubectl get rolebinding -n team-a
   ```

2. **Verify user identity in RoleBinding:**
   ```bash
   kubectl get rolebinding alice-team-a-admin -n team-a -o yaml
   ```
   Ensure the `subjects[].name` matches the exact email used in Omni

3. **Check Role exists:**
   ```bash
   kubectl get role team-a-admin -n team-a
   ```
   If missing, the tenant-baseline chart may not be deployed

### User can't download kubeconfig

1. **Verify Omni role:** User must have at least **Reader** role in Omni
2. **Check Omni access:** User should see the cluster in Omni dashboard

## ArgoCD Access

**Note:** Tenant users do **NOT** have access to ArgoCD UI.

- **ArgoCD** is for platform admins only (admin user + password)
- **Tenant users** manage their workloads via `kubectl`
- GitOps workflows are managed by platform team

If you need to give a user ArgoCD access for their tenant applications, you would need to:
1. Re-enable OIDC/SSO in ArgoCD (currently disabled)
2. Configure ArgoCD RBAC policies per tenant
3. This is more complex and not currently configured

## Adding a New Tenant

See [CLAUDE.md](../CLAUDE.md#multi-tenant-pattern) for full tenant creation workflow.

Quick summary:
1. Create `tenants/{tenant-name}/tenant.values.yaml`
2. Customize resources, quotas, network policies
3. ArgoCD auto-discovers and deploys
4. Add user RoleBindings in `tenants/{tenant-name}/resources/`
