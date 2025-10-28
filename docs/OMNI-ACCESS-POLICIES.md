# Omni Access Policies (ACLs)

This guide explains how to use Omni's **Access Policies** for advanced multi-tenant user management.

## Overview

**Access Policies** provide much more control than basic Omni roles (None/Reader/Operator/Admin):

- ✅ **Per-cluster permissions** - different access levels per cluster
- ✅ **Kubernetes group impersonation** - automatically add users to K8s groups
- ✅ **User groups** - manage groups of users together
- ✅ **Cluster groups** - apply policies to multiple clusters
- ✅ **Declarative** - manage via YAML files and Git

## Why Use Access Policies?

### Without Access Policies (Current Simple Setup)

1. Create Omni user → assign global role
2. Create individual RoleBinding per user per namespace
3. Update RoleBinding when user changes

**Problems:**
- One RoleBinding file per user per namespace
- No centralized user group management
- Manual updates when users join/leave teams

### With Access Policies

1. Define user groups in `access-policy.yaml`
2. Map groups to K8s groups via impersonation
3. Create ONE RoleBinding per group (not per user!)
4. Users automatically get access based on group membership

**Benefits:**
- ✅ Centralized user management
- ✅ One RoleBinding per team (not per user)
- ✅ Easier to add/remove users
- ✅ Works great with GitOps

## How It Works

### 1. Omni Access Policy

Define in `docs/omni-access-policy.yaml`:

```yaml
metadata:
  namespace: default
  type: AccessPolicies.omni.sidero.dev
  id: access-policy
spec:
  usergroups:
    team-a-members:
      - alice@matjah.dev
      - charlie@matjah.dev

  rules:
    - usergroups:
        - team-a-members
      clusters:
        - talos-default
      kubernetes:
        impersonate:
          groups:
            - team-a-admins  # K8s group added automatically
      role: Reader
```

**Apply it:**
```bash
omnictl apply -f docs/omni-access-policy.yaml
```

### 2. Kubernetes RoleBinding (Using Groups)

Create ONE RoleBinding for the **group** in `tenants/team-a/resources/`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-admins-binding
  namespace: team-a
subjects:
- kind: Group
  name: team-a-admins  # Matches impersonation group
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-admin
  apiGroup: rbac.authorization.k8s.io
```

**Apply it:**
```bash
kubectl apply -f tenants/team-a/resources/group-rolebinding.yaml
```

### 3. How User Access Works

1. **Alice** downloads kubeconfig from Omni
2. Access Policy automatically adds her to K8s group: `team-a-admins`
3. RoleBinding grants `team-a-admins` group access to team-a namespace
4. Alice can now manage team-a resources!

**No per-user RoleBinding needed!**

## Current Access Policy

View your current policy:

```bash
omnictl get accesspolicy access-policy -o yaml
```

Your cluster already has access policies configured with:
- Alice: team-a group impersonation
- Bob: team-b group impersonation

## Complete Example

See [docs/omni-access-policy.yaml](omni-access-policy.yaml) for a full example with:
- Platform admins group
- Team A members group
- Team B members group
- Kubernetes group impersonation per team

## Migration Path: Individual RoleBindings → Group-Based

### Current Setup (Individual Users)
```
tenants/team-a/resources/
├── alice-rolebinding.yaml    # Binds alice@matjah.dev to team-a-admin
├── charlie-rolebinding.yaml  # Binds charlie@matjah.dev to team-a-admin
└── dave-rolebinding.yaml     # Binds dave@matjah.dev to team-a-admin
```

### New Setup (Group-Based)
```
tenants/team-a/resources/
└── group-rolebinding.yaml    # Binds team-a-admins GROUP to team-a-admin

docs/
└── omni-access-policy.yaml   # Defines which users are in team-a-admins
```

**Migration steps:**

1. **Apply Access Policy** with group impersonation:
   ```bash
   omnictl apply -f docs/omni-access-policy.yaml
   ```

2. **Create group RoleBinding:**
   ```bash
   kubectl apply -f tenants/team-a/resources/group-rolebinding.yaml
   ```

3. **Test user access:** Have users download fresh kubeconfig

4. **Delete individual RoleBindings:**
   ```bash
   kubectl delete rolebinding alice-rolebinding -n team-a
   kubectl delete rolebinding charlie-rolebinding -n team-a
   ```

## Access Policy Structure

### User Groups

Define reusable groups of users:

```yaml
spec:
  usergroups:
    platform-team:
      - admin@company.com
      - devops@company.com

    team-a-admins:
      - alice@matjah.dev

    team-a-developers:
      - bob@matjah.dev
      - charlie@matjah.dev
```

### Cluster Groups

Define groups of clusters (useful for multi-cluster):

```yaml
spec:
  clustergroups:
    production:
      - prod-cluster-1
      - prod-cluster-2

    development:
      - dev-cluster-1
      - talos-default
```

### Rules

Map users/groups to clusters with roles:

```yaml
spec:
  rules:
    # Rule 1: Platform admins
    - usergroups:
        - platform-team
      clustergroups:
        - production
        - development
      role: Admin

    # Rule 2: Team A members
    - usergroups:
        - team-a-admins
        - team-a-developers
      clusters:
        - talos-default
      kubernetes:
        impersonate:
          groups:
            - team-a-admins
      role: Reader

    # Rule 3: Individual contractor
    - users:
        - contractor@external.com
      clusters:
        - dev-cluster-1
      kubernetes:
        impersonate:
          groups:
            - team-a-viewers
      role: Reader
```

## Kubernetes Group Impersonation

**Most powerful feature!** Automatically add users to K8s groups:

```yaml
kubernetes:
  impersonate:
    groups:
      - team-a-admins      # Primary group
      - all-developers     # Additional groups
      - monitoring-viewers
```

When users download kubeconfig, these groups are **automatically injected** into their certificates.

## Omni Roles in Access Policies

Each rule assigns an **Omni role** per cluster:

- **Admin**: Full Omni cluster management (create/delete nodes, etc.)
- **Operator**: Deploy/manage workloads, update configs
- **Reader**: View-only + download kubeconfig

**Note:** For tenant users, use **Reader** role + Kubernetes group impersonation. They get namespace access via K8s RBAC, not Omni role.

## Workflow: Adding a New User

### Old Way (Individual RoleBindings)
1. Create Omni user
2. Assign Reader role globally
3. Create RoleBinding YAML file
4. Apply RoleBinding
5. Commit to Git

### New Way (Access Policies)
1. Create Omni user
2. Add to `usergroups` in `docs/omni-access-policy.yaml`
3. Apply Access Policy: `omnictl apply -f docs/omni-access-policy.yaml`
4. Done! (RoleBindings already exist for the group)

**Much simpler!**

## Workflow: Removing a User

### Old Way
1. Delete RoleBinding from Git
2. Apply changes to cluster
3. Commit

### New Way
1. Remove user from `usergroups` in `docs/omni-access-policy.yaml`
2. Apply: `omnictl apply -f docs/omni-access-policy.yaml`
3. Commit
4. User immediately loses access (on next kubeconfig refresh)

## Commands

### View current policy
```bash
omnictl get accesspolicies
omnictl get accesspolicy access-policy -o yaml
```

### Apply policy
```bash
omnictl apply -f docs/omni-access-policy.yaml
```

### Export current policy
```bash
omnictl get accesspolicy access-policy -o yaml > docs/omni-access-policy.yaml
```

### Validate policy (dry-run)
```bash
# Test if user alice@matjah.dev can access cluster
omnictl get accesspolicy access-policy -o yaml | grep -A5 "alice@matjah.dev"
```

## Multi-Cluster Example

If you have multiple clusters:

```yaml
spec:
  clustergroups:
    production:
      - prod-us-east
      - prod-eu-west
    staging:
      - staging-cluster

  rules:
    # Production access (read-only)
    - users:
        - developer@company.com
      clustergroups:
        - production
      role: Reader
      kubernetes:
        impersonate:
          groups:
            - developers-readonly

    # Staging access (full)
    - users:
        - developer@company.com
      clustergroups:
        - staging
      role: Operator
      kubernetes:
        impersonate:
          groups:
            - developers-admin
```

Same user, different roles per cluster!

## Best Practices

1. **Use user groups** instead of individual users in rules
2. **Use K8s group impersonation** to avoid per-user RoleBindings
3. **Keep Access Policy in Git** (`docs/omni-access-policy.yaml`)
4. **Apply via CI/CD** for audit trail
5. **Use descriptive group names** (team-a-admins, not group1)
6. **Document group purposes** in comments

## Troubleshooting

### User doesn't have expected K8s groups

1. **Check Access Policy:**
   ```bash
   omnictl get accesspolicy access-policy -o yaml | grep -A10 "user@example.com"
   ```

2. **User needs to download fresh kubeconfig:**
   ```bash
   omnictl kubeconfig talos-default > ~/.kube/config --force
   ```

3. **Verify groups in kubeconfig:**
   ```bash
   kubectl config view --raw | grep -A5 "impersonate"
   ```

### Changes not taking effect

- Access Policy changes require users to **download new kubeconfig**
- Omni caches policies; changes may take 1-2 minutes

### Group RoleBinding not working

1. **Check RoleBinding exists:**
   ```bash
   kubectl get rolebinding -n team-a
   ```

2. **Verify group name matches:**
   ```bash
   # In Access Policy
   kubernetes.impersonate.groups: ["team-a-admins"]

   # In RoleBinding
   subjects[].name: "team-a-admins"
   ```

## See Also

- [TENANT-USER-MANAGEMENT.md](TENANT-USER-MANAGEMENT.md) - Individual user RoleBindings approach
- [CLAUDE.md](../CLAUDE.md) - Multi-tenant architecture overview
- Example: [docs/omni-access-policy.yaml](omni-access-policy.yaml)
- Example: [tenants/team-a/resources/group-rolebinding.yaml](../tenants/team-a/resources/group-rolebinding.yaml)
