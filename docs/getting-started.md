# Getting Started

This guide explains the basic concepts of the multi-tenant Kubernetes cluster.

## Overview

This cluster uses:
- **Omni** - Cluster lifecycle management
- **Kubernetes RBAC** - Namespace access control
- **Group-based permissions** - Simplified user management

## How It Works

### Authentication Flow

```
1. User logs into Omni (OIDC)
2. Omni Access Policy adds user to K8s group
3. User downloads kubeconfig
4. Kubernetes RoleBinding grants namespace access
5. User can access their assigned namespace
```

### Key Concepts

**Tenants**
- Isolated namespaces (team-a, team-b)
- Each tenant has resource quotas
- Network isolation between tenants

**User Groups**
- `team-a-admins` - Full access to team-a namespace
- `team-b-admins` - Full access to team-b namespace
- Groups defined in Omni Access Policy

**Omni Roles**
- `Reader` - Can download kubeconfig (used for tenant users)
- `Operator` - Can manage cluster resources
- `Admin` - Full Omni access

## Next Steps

- **[Add your first user](adding-users.md)**
- **[Understand namespace isolation](namespace-isolation.md)**
- **[Learn about access policies](access-policies.md)**
