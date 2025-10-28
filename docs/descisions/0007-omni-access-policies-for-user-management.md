# ADR-007: Omni Access Policies for User Management

**Status:** Accepted

**Date:** 2025-10-27

**Deciders:** Platform Team

## Context

The cluster initially used **GitHub SSO via ArgoCD Dex** for user authentication:
- Users authenticated via GitHub OAuth
- ArgoCD mapped GitHub teams to ArgoCD RBAC roles
- Required complex configuration: GitHub OAuth app, Dex connector, ArgoCD RBAC policies
- Required separate mechanism for kubectl access (not just ArgoCD UI)

When onboarding the first tenant user (alice@example.com), we discovered that:
1. The cluster is managed by **Omni platform** (Sidero Labs)
2. Omni provides its own **OIDC authentication**
3. Omni has **Access Policies** (ACLs) that can:
   - Map users to Kubernetes groups via kubeconfig impersonation
   - Control cluster access at platform level
   - Enable self-service kubeconfig download

This made GitHub SSO redundant and overly complex.

### Requirements

- **Multi-tenant user management**: Add/remove users without kubectl commands
- **Self-service kubeconfig**: Users download their own kubeconfigs
- **Kubernetes group impersonation**: Users automatically get K8s groups for RBAC
- **GitOps-friendly**: Access control defined in version-controlled YAML
- **Simple onboarding**: Add user by editing single file

## Decision

We will **remove GitHub SSO/Dex configuration** and use **Omni Access Policies** as the single authentication and authorization mechanism.

### Configuration

#### 1. Access Policy Definition

```yaml
# docs/omni-access-policy.yaml
metadata:
  type: AccessPolicies.omni.sidero.dev
  id: access-policy
spec:
  rules:
    # Team A users
    - users:
        - alice@example.com
        - charlie@example.com
      clusters:
        - talos-default
      kubernetes:
        impersonate:
          groups:
            - team-a-admins  # K8s RBAC group
      role: Reader           # Enables kubeconfig download

    # Team B users
    - users:
        - bob@example.com
      clusters:
        - talos-default
      kubernetes:
        impersonate:
          groups:
            - team-b-admins
      role: Reader
```

**How it works:**
1. User authenticates to Omni platform (username/password or SSO)
2. Omni evaluates Access Policy for user's email
3. Generates kubeconfig with OIDC auth + group impersonation
4. User downloads kubeconfig from Omni dashboard/CLI
5. kubectl commands use OIDC to authenticate, K8s sees user in specified groups

#### 2. Apply Policy

```bash
# Apply from local file
omnictl apply -f docs/omni-access-policy.yaml

# Verify
omnictl get accesspolicy access-policy -o yaml
```

**Changes take effect immediately** - no cluster restart required.

#### 3. User Workflow

**For users:**
```bash
# 1. Access Omni dashboard or CLI
omnictl login

# 2. Download kubeconfig
omnictl kubeconfig talos-default > ~/.kube/config

# 3. Use kubectl immediately
kubectl get pods -n team-a  # Works (user is in team-a-admins group)
kubectl get pods -n team-b  # Forbidden (not in team-b-admins group)
```

#### 4. ArgoCD Simplification

ArgoCD configuration simplified to **admin-only**:

```yaml
# apps/argocd/argocd/config.yaml
data:
  admin.enabled: "true"
  # No Dex configuration

# apps/argocd/argocd/rbac-cm.yaml
data:
  policy.csv: |
    # ArgoCD RBAC - Admin Only
    # Tenant users access K8s directly via kubectl
  policy.default: role:readonly
```

**Tenant users:**
- Access Kubernetes via kubectl (not ArgoCD UI)
- Manage their workloads with standard K8s tools
- No need for ArgoCD UI access

**Platform admins:**
- Access ArgoCD via admin account
- Manage GitOps applications
- Monitor cluster-wide sync status

### Omni Role Selection: Reader

**Why `role: Reader` (not `None` or `Operator`):**

- **`None`**: User cannot download kubeconfig (requires admin intervention)
- **`Reader`**: User can download kubeconfig, view cluster resources
- **`Operator`**: User can manage cluster lifecycle (too much access)

**Trade-off with `Reader`:**
- Users can **view** other namespaces (list pods, services, etc.)
- Users **cannot modify** other namespaces (enforced by K8s RBAC)
- This is **industry-standard behavior** for Kubernetes OIDC authentication

See [ADR-009: Read Visibility vs Write Isolation](009-read-visibility-vs-write-isolation.md) for detailed analysis.

## Consequences

### Positive

- **Single source of truth**: One YAML file for all access control
- **Self-service**: Users download kubeconfigs without admin help
- **Simplified architecture**: Removed ~300 lines of SSO configuration
- **Native Omni integration**: Leverages platform features
- **Immediate updates**: Policy changes apply without cluster restart
- **GitOps-friendly**: Access Policy version-controlled in Git
- **No external dependencies**: No GitHub OAuth, no Dex
- **Better separation**: Platform admins use ArgoCD, tenant users use kubectl

### Negative

- **Omni platform dependency**: Users must have Omni access
  - **Acceptable**: Cluster is Omni-managed by design
- **No ArgoCD UI for tenants**: Tenants can't use ArgoCD UI
  - **Acceptable**: Tenants primarily use kubectl, not ArgoCD
- **Read visibility**: Users can view (not modify) other namespaces
  - **Acceptable**: Industry-standard OIDC behavior
- **Learning curve**: Platform admins must learn Omni Access Policies

### Neutral

- **User syntax**: Currently using direct user lists (not usergroups/clustergroups)
  - **Reason**: usergroups/clustergroups syntax appeared unsupported or undocumented
  - **Impact**: Works fine for small number of users, may need refactor for large scale

## Alternatives Considered

### Alternative 1: Keep GitHub SSO via Dex
**Rejected**: Overly complex
- **Problem**: Required GitHub OAuth app, Dex config, ArgoCD RBAC policies
- **Problem**: Separate mechanism needed for kubectl access
- **Problem**: Two authentication paths (GitHub + Omni)

### Alternative 2: Generic OIDC Provider (Keycloak, Okta)
**Rejected**: Redundant with Omni OIDC
- **Problem**: Additional component to deploy and manage
- **Problem**: Omni already provides OIDC

### Alternative 3: Kubernetes RBAC Only (no Omni policies)
**Rejected**: No cluster-level access control
- **Problem**: Can't restrict which users access the cluster at all
- **Problem**: All K8s-authenticated users would have some access

### Alternative 4: Client Certificates
**Rejected**: Difficult to manage and rotate
- **Problem**: Must generate and distribute certificates per user
- **Problem**: No self-service, admin must create certs
- **Problem**: Certificate rotation is manual and error-prone

## Related Decisions

- [ADR-008: Group-Based RBAC Over Individual User Bindings](008-group-based-rbac-over-individual-user-bindings.md)
- [ADR-009: Read Visibility vs Write Isolation](009-read-visibility-vs-write-isolation.md)

## References

- [docs/omni-access-policy.yaml](../omni-access-policy.yaml) - Current Access Policy
- [docs/access-policies-reference.md](../access-policies-reference.md) - Complete ACL guide
- [docs/adding-users.md](../adding-users.md) - User onboarding workflow
- [Omni ACL Documentation](https://docs.siderolabs.com/omni/reference/acls)
- Commits: [38a3efb](../../.git) (added ACL), [8e11d86](../../.git) (removed SSO)
