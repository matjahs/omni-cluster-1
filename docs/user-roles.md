# User Roles

Available roles and their permissions in the multi-tenant cluster.

## Omni Roles

Assigned in Omni Dashboard or Access Policy:

| Role | Kubeconfig Download | Cluster View | Use Case |
|------|---------------------|--------------|----------|
| **Reader** | ✅ Yes | View-only | Tenant users |
| **Operator** | ✅ Yes | Full | Platform team |
| **Admin** | ✅ Yes | Full | Administrators |
| **None** | ❌ No | None | Not used |

**For tenant users, use:** `Reader`

## Kubernetes Roles (per namespace)

Defined in `tenants/*/resources/` via Helm chart:

### Admin

**Full access** within the namespace.

**Can do:**
- Create/delete/modify all resources
- View secrets and configmaps
- Execute into pods
- View logs

**Use case:** Tenant owners, lead developers

### Developer

**Read/write access** to common resources.

**Can do:**
- Manage pods, deployments, services
- View logs and exec into pods
- Create configmaps and secrets

**Cannot do:**
- Modify RBAC resources
- Change resource quotas

**Use case:** Development team members

### Viewer

**Read-only access** to all resources.

**Can do:**
- View resources
- View logs

**Cannot do:**
- Modify anything

**Use case:** Auditors, read-only monitoring

## Current Mapping

| User | Omni Role | K8s Group | Namespace | K8s Role |
|------|-----------|-----------|-----------|----------|
| alice@example.com | Reader | team-a-admins | team-a | Admin |
| charlie@example.com | Reader | team-a-admins | team-a | Admin |
| bob@example.com | Reader | team-b-admins | team-b | Admin |

## Changing User Roles

To change a user's Kubernetes role, modify the Access Policy to assign them to a different group:

```yaml
# Give user developer access instead of admin
- users:
    - newuser@example.com
  kubernetes:
    impersonate:
      groups:
        - team-a-developers  # Instead of team-a-admins
  role: Reader
```

Then ensure the appropriate RoleBinding exists in the namespace.

## See Also

- **[Adding Users](adding-users.md)** - User onboarding
- **[Access Policies](access-policies.md)** - Complete ACL reference
