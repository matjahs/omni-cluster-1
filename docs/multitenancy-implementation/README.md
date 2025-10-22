# Multi-tenancy Implementation Files

This directory contains ready-to-use configuration files for implementing multi-tenant authentication and authorization in your Kubernetes cluster.

## Directory Structure

```
multitenancy-implementation/
├── README.md                           # This file
├── QUICKSTART.md                       # Step-by-step implementation guide
├── argocd-projects/                    # Per-tenant ArgoCD AppProjects
│   ├── team-a-project.yaml
│   └── team-b-project.yaml
├── argocd-rbac/                        # ArgoCD RBAC and SSO configuration
│   ├── rbac-cm.yaml                    # RBAC policies
│   ├── config-sso-github.yaml          # GitHub SSO example
│   └── config-sso-generic-oidc.yaml    # Generic OIDC example
├── tenant-rbac/                        # Kubernetes namespace RBAC
│   └── team-a-rbac.yaml
└── vault-policies/                     # Vault policies and setup
    └── setup-vault-multitenancy.sh
```

## Quick Links

- **[Full Proposal](../multitenancy-proposal.md)** - Detailed architecture and design
- **[Quick Start Guide](./QUICKSTART.md)** - Get started in 30 minutes

## Implementation Paths

### Path 1: Testing (Local Users)
Best for development and POC.

1. Apply AppProjects
2. Configure RBAC
3. Create local users
4. Test login

**Time: ~30 minutes**

### Path 2: Production (SSO)
Best for production environments.

1. Setup SSO provider (GitHub/OIDC)
2. Apply AppProjects
3. Configure SSO in ArgoCD
4. Configure RBAC with group mappings
5. Setup Vault multi-tenancy

**Time: ~2-3 hours**

## Files Overview

### ArgoCD Projects

- **team-a-project.yaml** / **team-b-project.yaml**
  - Restricts applications to specific namespaces
  - Defines allowed source repositories
  - Configures project-level roles (admin, developer, viewer)

### ArgoCD RBAC

- **rbac-cm.yaml**
  - Maps groups to roles
  - Defines permissions for each role
  - Works with both local users and SSO groups

- **config-sso-github.yaml**
  - GitHub OAuth configuration
  - Includes ExternalSecret for credentials from Vault

- **config-sso-generic-oidc.yaml**
  - Generic OIDC configuration (Keycloak, Okta, Auth0)
  - Template for any OIDC-compliant provider

### Kubernetes RBAC

- **team-a-rbac.yaml**
  - Namespace-level Roles (admin, developer, viewer)
  - RoleBindings to groups
  - Service accounts for CI/CD

### Vault Policies

- **setup-vault-multitenancy.sh**
  - Creates Vault policies per tenant
  - Creates Kubernetes auth roles
  - Configures secret path isolation

## Customization

### Adding a New Tenant

1. **Copy and modify AppProject:**
   ```bash
   cp argocd-projects/team-a-project.yaml argocd-projects/team-c-project.yaml
   # Edit to change 'team-a' to 'team-c'
   ```

2. **Add RBAC rules:**
   - Edit `argocd-rbac/rbac-cm.yaml`
   - Add team-c groups and roles

3. **Create Kubernetes RBAC:**
   ```bash
   cp tenant-rbac/team-a-rbac.yaml tenant-rbac/team-c-rbac.yaml
   # Edit to change namespace and role names
   ```

4. **Update Vault script:**
   - Edit `vault-policies/setup-vault-multitenancy.sh`
   - Add team-c policy and role

### Modifying Permissions

**ArgoCD Permissions:**
- Edit `argocd-rbac/rbac-cm.yaml`
- Modify policy.csv rules
- See [ArgoCD RBAC docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)

**Kubernetes Permissions:**
- Edit `tenant-rbac/team-a-rbac.yaml`
- Modify rules in Role definitions
- See [Kubernetes RBAC docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

**Vault Permissions:**
- Edit `vault-policies/setup-vault-multitenancy.sh`
- Modify HCL policy blocks
- See [Vault policies docs](https://developer.hashicorp.com/vault/docs/concepts/policies)

## Security Best Practices

1. **Always use groups, never individual users**
   - Manage group membership in your SSO provider
   - ArgoCD/Kubernetes RBAC references groups

2. **Principle of least privilege**
   - Start with viewer role
   - Grant developer access as needed
   - Admin access only when required

3. **Separate concerns**
   - ArgoCD for GitOps control
   - Kubernetes RBAC for runtime access
   - Vault for secrets management

4. **Regular audits**
   - Review group memberships quarterly
   - Check ArgoCD audit logs
   - Monitor Vault access patterns

5. **Use SSO MFA**
   - Enable MFA in your SSO provider
   - Don't rely on passwords alone

## Testing

### Verify ArgoCD RBAC

```bash
# As team-a user
argocd login <server> --username team-a-admin --password <password>
argocd app list  # Should only show team-a apps

# As team-b user
argocd login <server> --username team-b-admin --password <password>
argocd app list  # Should only show team-b apps
```

### Verify Vault Isolation

```bash
# Login with team-a credentials
vault login -method=kubernetes role=team-a

# Should succeed
vault kv get kv/team-a/demo

# Should fail
vault kv get kv/team-b/demo
```

### Verify Kubernetes RBAC

```bash
# As team-a developer
kubectl auth can-i create deployment -n team-a  # yes
kubectl auth can-i create deployment -n team-b  # no
kubectl auth can-i delete namespace -n team-a   # no
```

## Support

- **Issues**: File in the repository issue tracker
- **Questions**: See [QUICKSTART.md](./QUICKSTART.md) troubleshooting section
- **ArgoCD RBAC**: https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/
- **Vault Policies**: https://developer.hashicorp.com/vault/docs/concepts/policies
