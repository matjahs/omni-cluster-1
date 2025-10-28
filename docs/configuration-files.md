# Configuration Files

Important files and their locations.

## Access Control

### `docs/omni-access-policy.yaml`
**Purpose:** Defines which users can access which namespaces.

**Contains:**
- User to Kubernetes group mappings
- Omni role assignments
- Cluster access rules

**How to edit:**
```bash
vim docs/omni-access-policy.yaml
omnictl apply -f docs/omni-access-policy.yaml
```

---

## Tenant Configuration

### `tenants/team-a/tenant.values.yaml`
**Purpose:** Tenant-specific configuration (quotas, RBAC groups, network policies).

**Example:**
```yaml
tenantName: team-a
rbac:
  adminGroups:
    - team-a-admins
resourceQuota:
  hard:
    requests.cpu: '4'
    limits.memory: 16Gi
```

---

## RBAC Resources

### `tenants/team-a/resources/group-rolebinding.yaml`
**Purpose:** Binds Kubernetes group to namespace Role.

**Maps:**
- K8s Group: `team-a-admins`
- To Role: `team-a-admin`
- In Namespace: `team-a`

### `tenants/team-a/resources/team-a-admin-role.yaml`
**Purpose:** Defines permissions for the admin role.

**Grants:** Full access (`*` on `*`) within namespace.

---

## Helm Charts

### `helm/tenant-baseline/`
**Purpose:** Baseline Helm chart for all tenants.

**Provides:**
- RBAC templates
- Resource quotas
- Network policies
- Pod security standards

**Files:**
- `Chart.yaml` - Chart metadata
- `values.yaml` - Default values
- `templates/rbac.yaml` - RBAC templates
- `templates/networkpolicy.yaml` - Network isolation

---

## File Tree

```
docs/
├── omni-access-policy.yaml        # Omni ACL configuration
└── *.md                           # Documentation

tenants/
├── team-a/
│   ├── tenant.values.yaml         # Tenant config
│   └── resources/
│       ├── group-rolebinding.yaml # K8s RBAC
│       └── team-a-admin-role.yaml # K8s Role
└── team-b/
    └── resources/
        ├── group-rolebinding.yaml
        └── team-b-admin-role.yaml

helm/
└── tenant-baseline/               # Baseline Helm chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── rbac.yaml
        ├── networkpolicy.yaml
        └── ...
```

---

## Quick Commands

**View current Access Policy:**
```bash
omnictl get accesspolicy access-policy -o yaml
```

**Check RoleBindings:**
```bash
kubectl get rolebindings -n team-a
```

**Test user permissions:**
```bash
kubectl auth can-i get pods --as=user@example.com --as-group=team-a-admins -n team-a
```

---

## See Also

- **[Adding Users](adding-users.md)** - User onboarding
- **[Access Policies](access-policies.md)** - Complete ACL reference
