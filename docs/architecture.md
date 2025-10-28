# Architecture

System design and authentication flow.

## Multi-Tenant Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Omni Platform                        │
│  (OIDC Provider + Cluster Management)                   │
└─────────────────┬───────────────────────────────────────┘
                  │
                  │ 1. User authenticates
                  ↓
┌─────────────────────────────────────────────────────────┐
│              Access Policy (ACL)                        │
│  - Maps users to Kubernetes groups                     │
│  - Defines Omni roles (Reader/Operator/Admin)          │
└─────────────────┬───────────────────────────────────────┘
                  │
                  │ 2. Group impersonation added to kubeconfig
                  ↓
┌─────────────────────────────────────────────────────────┐
│            Kubernetes API Server                        │
│  (RBAC enforcement via RoleBindings)                    │
└─────────────────┬───────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ↓                   ↓
┌───────────────┐   ┌───────────────┐
│  Namespace    │   │  Namespace    │
│   team-a      │   │   team-b      │
│               │   │               │
│ RoleBinding:  │   │ RoleBinding:  │
│ team-a-admins │   │ team-b-admins │
│ → team-a-admin│   │ → team-b-admin│
└───────────────┘   └───────────────┘
```

## Authentication Flow

### Step 1: User Login
```
User → Omni Dashboard → OIDC Login
```

### Step 2: Access Policy Evaluation
```
Omni checks Access Policy:
- Is user in policy?
- Which K8s groups to add?
- What Omni role?
```

### Step 3: Kubeconfig Generation
```
Kubeconfig includes:
- Cluster endpoint
- OIDC auth config
- Group impersonation (team-a-admins)
```

### Step 4: Kubernetes Authorization
```
K8s API Server:
- Checks RoleBindings for user's groups
- Grants permissions based on Role
- Enforces namespace boundaries
```

## Components

### Omni
- Cluster lifecycle management
- OIDC authentication provider
- Access Policy enforcement
- Kubeconfig generation

### Access Policy (ACL)
- User to K8s group mapping
- Omni role assignment
- Stored as Kubernetes Custom Resource

### Kubernetes RBAC
- **Role**: Permissions within namespace
- **RoleBinding**: Maps group to Role
- **Namespace**: Isolation boundary

### Tenant Baseline Chart
- Helm chart providing:
  - RBAC templates
  - Resource quotas
  - Network policies
  - Pod security standards

## Data Flow: User Creates Pod

```
1. kubectl create pod → K8s API Server
2. API Server checks RBAC:
   - Extract groups from kubeconfig (team-a-admins)
   - Find RoleBindings for team-a-admins
   - Check if Role allows "create pods"
3. If allowed → Pod created
4. If denied → 403 Forbidden
```

## File Structure

```
Repository
├── docs/
│   ├── omni-access-policy.yaml    # Access Policy config
│   └── *.md                       # Documentation
│
├── tenants/
│   ├── team-a/
│   │   ├── tenant.values.yaml     # Overrides for tenant
│   │   └── resources/
│   │       └── group-rolebinding.yaml  # K8s RBAC
│   └── team-b/
│
└── helm/
    └── tenant-baseline/           # Base Helm chart
        ├── values.yaml            # Defaults
        └── templates/
            ├── rbac.yaml          # RBAC templates
            ├── networkpolicy.yaml # Network isolation
            └── quota.yaml         # Resource limits
```

## Key Design Decisions

### Group-Based RBAC
**Why:** One RoleBinding per group vs. one per user.

**Benefit:** Add users by updating Access Policy only. No kubectl needed.

### Omni Role: Reader
**Why:** Users can self-service download kubeconfig.

**Trade-off:** Users can view (but not modify) other namespaces.

### Network Policies
**Why:** Defense in depth. Even if RBAC is misconfigured, pods can't communicate cross-tenant.

**Implementation:** Cilium NetworkPolicy via tenant-baseline chart.

## Security Layers

| Layer | Mechanism | Enforces |
|-------|-----------|----------|
| 1. Authentication | Omni OIDC | User identity |
| 2. Access Policy | Omni ACL | Group membership |
| 3. RBAC | K8s RoleBindings | Namespace access |
| 4. Network | Cilium Policies | Pod-to-pod traffic |
| 5. Resources | Resource Quotas | CPU/memory limits |

## See Also

- **[Getting Started](getting-started.md)** - Basic concepts
- **[Access Policies](access-policies.md)** - ACL deep dive
- **[Configuration Files](configuration-files.md)** - File locations
