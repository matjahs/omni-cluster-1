# ADR-008: Group-Based RBAC Over Individual User Bindings

**Status:** Accepted

**Date:** 2025-10-27

**Deciders:** Platform Team

## Context

When implementing multi-tenant access control, there are two approaches for Kubernetes RBAC:

### Approach 1: Per-User RoleBindings
```yaml
# One RoleBinding per user
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-admin-binding
  namespace: team-a
subjects:
- kind: User
  name: alice@example.com
roleRef:
  kind: Role
  name: team-a-admin
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: charlie-admin-binding
  namespace: team-a
subjects:
- kind: User
  name: charlie@example.com
roleRef:
  kind: Role
  name: team-a-admin
```

**Adding a user requires:**
1. Edit `tenants/team-a/resources/new-user-rolebinding.yaml`
2. Commit to Git
3. Wait for ArgoCD sync
4. Edit `docs/omni-access-policy.yaml`
5. Apply with `omnictl apply -f ...`

**Operational burden:**
- N RoleBindings per tenant (where N = number of users)
- Git commits for every user add/remove
- ArgoCD sync required for RBAC changes

### Approach 2: Group-Based RoleBindings
```yaml
# Single RoleBinding per group
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-admins-binding
  namespace: team-a
subjects:
- kind: Group
  name: team-a-admins  # All users in this group
roleRef:
  kind: Role
  name: team-a-admin
```

**Adding a user requires:**
1. Edit `docs/omni-access-policy.yaml` (add user to group)
2. Apply with `omnictl apply -f ...`
3. Done - no Git commit or ArgoCD sync needed

**Operational burden:**
- 1 RoleBinding per tenant (constant, regardless of users)
- No Git commits for user changes
- No ArgoCD sync required

## Decision

We will use **Group-Based RoleBindings** where:
1. **Omni Access Policy** maps users to Kubernetes groups
2. **Kubernetes RoleBindings** bind groups (not users) to Roles

### Implementation

#### 1. Omni Access Policy (Group Impersonation)

```yaml
# docs/omni-access-policy.yaml
spec:
  rules:
    - users:
        - alice@example.com
        - charlie@example.com
      clusters:
        - talos-default
      kubernetes:
        impersonate:
          groups:
            - team-a-admins  # K8s group added to kubeconfig
      role: Reader
```

**How it works:**
- Omni generates kubeconfig with group impersonation
- When user authenticates via OIDC, K8s API sees them as member of `team-a-admins` group

#### 2. Kubernetes RoleBinding (Group to Role)

```yaml
# tenants/team-a/resources/group-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-admins-binding
  namespace: team-a
subjects:
- kind: Group
  name: team-a-admins  # Matches Access Policy group
roleRef:
  kind: Role
  name: team-a-admin
```

**Static configuration:**
- RoleBinding is deployed once via GitOps
- Never changes when adding/removing users
- Only changes when modifying permissions (Role) or group name

#### 3. User Onboarding Workflow

**To add a user:**
```bash
# 1. Edit Access Policy
vim docs/omni-access-policy.yaml
# Add user to appropriate rule

# 2. Apply policy
omnictl apply -f docs/omni-access-policy.yaml

# 3. Done! No Git commit or kubectl needed.
```

**To remove a user:**
```bash
# 1. Edit Access Policy
vim docs/omni-access-policy.yaml
# Remove user from rules

# 2. Apply policy
omnictl apply -f docs/omni-access-policy.yaml

# 3. Done!
```

**User's existing kubeconfig immediately loses access** (next kubectl command will be denied).

### Verification

```bash
# Check what groups a user is in
kubectl auth can-i get pods --as=alice@example.com \
  --as-group=team-a-admins -n team-a
# Output: yes

kubectl auth can-i get pods --as=alice@example.com \
  --as-group=team-a-admins -n team-b
# Output: no
```

## Consequences

### Positive

- **Simplified operations**: Add/remove users without Git commits
- **No ArgoCD sync required**: RBAC changes independent of GitOps
- **Faster onboarding**: Single `omnictl apply` command
- **Fewer resources**: 1 RoleBinding per tenant (not per user)
- **Cleaner Git history**: No commits for every user change
- **Scalable**: Adding 100th user is same effort as 1st user
- **Audit trail**: All access changes in Omni Access Policy history

### Negative

- **Omni dependency**: User-to-group mapping only in Omni
  - **Acceptable**: Cluster is Omni-managed by design
- **Group naming convention**: Must coordinate group names between Access Policy and RoleBindings
  - **Mitigation**: Use consistent pattern (`<tenant>-admins`)

### Neutral

- **Group granularity**: Currently one admin group per tenant
  - **Future**: Could add viewer groups (`team-a-viewers`)
- **Role changes**: Still require Git commit to modify Role permissions (as expected)

## Alternatives Considered

### Alternative 1: Per-User RoleBindings
**Rejected**: Operational overhead
- **Problem**: N RoleBindings per tenant
- **Problem**: Git commit + ArgoCD sync for every user
- **Problem**: Doesn't scale beyond ~10 users per tenant

### Alternative 2: ClusterRoleBindings for Tenants
**Rejected**: Too broad
- **Problem**: Grants cluster-wide access
- **Problem**: Breaks tenant isolation

### Alternative 3: Dynamic RBAC via Admission Controller
**Rejected**: Added complexity
- **Problem**: Requires custom admission controller
- **Problem**: Additional component to maintain
- **Problem**: RBAC stored in controller, not Git

### Alternative 4: Kubernetes ServiceAccount Tokens
**Rejected**: No user identity
- **Problem**: All users share same ServiceAccount
- **Problem**: No audit trail of who performed actions
- **Problem**: Can't revoke individual user access

## Related Decisions

- [ADR-007: Omni Access Policies for User Management](007-omni-access-policies-for-user-management.md)
- Pattern inspired by standard Kubernetes RBAC best practices

## References

- [tenants/team-a/resources/group-rolebinding.yaml](../../tenants/team-a/resources/group-rolebinding.yaml)
- [docs/omni-access-policy.yaml](../omni-access-policy.yaml)
- [docs/adding-users.md](../adding-users.md) - User onboarding workflow
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- Commit: [c11ab9e](../../.git)
