# ADR-001: Use Omni Access Policies Instead of SSO

**Status:** Accepted

**Date:** 2025-10-28

**Deciders:** Platform Team

## Context

The cluster was initially configured with GitHub SSO via ArgoCD Dex connector, requiring complex configuration across multiple systems:
- GitHub OAuth application setup
- Dex connector configuration in ArgoCD
- RBAC policies mapping GitHub teams to ArgoCD roles
- Manual user management scripts

This approach had several challenges:
1. **Multiple authentication paths**: Users needed GitHub access for ArgoCD UI, separate approach for kubectl
2. **Operational complexity**: Changes required updates to multiple configuration files and GitHub settings
3. **Limited self-service**: Users couldn't download kubeconfigs without admin intervention
4. **ArgoCD dependency**: Tenant users needed ArgoCD UI access even though they primarily use kubectl

When adding the first tenant user (alice@example.com), we discovered Omni's built-in Access Policy system that provides:
- Native OIDC authentication via Omni platform
- Kubernetes group impersonation via kubeconfig
- Self-service kubeconfig download
- Fine-grained cluster access control

## Decision

We will **remove all GitHub/Dex SSO configuration** and use **Omni Access Policies** as the single authentication and authorization mechanism for tenant users.

**Implementation:**
1. Create `docs/omni-access-policy.yaml` defining user-to-group mappings
2. Apply policies via `omnictl apply -f docs/omni-access-policy.yaml`
3. Users authenticate via Omni dashboard/CLI and download kubeconfigs
4. Kubeconfigs include OIDC authentication and group impersonation
5. Kubernetes RBAC enforces namespace-level permissions

**ArgoCD access:**
- Simplified to admin-only (local admin account)
- Removed Dex configuration from `apps/argocd/argocd/config.yaml`
- Removed GitHub team mappings from `apps/argocd/argocd/rbac-cm.yaml`
- Tenant users access Kubernetes directly via kubectl, not ArgoCD UI

## Consequences

### Positive

- **Single source of truth**: All access control defined in one YAML file (`omni-access-policy.yaml`)
- **Self-service**: Users download kubeconfigs from Omni without admin intervention
- **Simplified operations**: Add users by editing Access Policy only, no kubectl/GitHub changes needed
- **Native Omni integration**: Leverages platform features instead of external SSO
- **Reduced configuration**: Removed ~200 lines of Dex/SSO configuration
- **Better separation of concerns**: Platform admins use ArgoCD, tenant users use kubectl

### Negative

- **Omni dependency**: Users must have Omni platform access (acceptable for Omni-managed clusters)
- **No ArgoCD UI for tenants**: Tenant users can't use ArgoCD UI (mitigated: they primarily use kubectl)
- **Learning curve**: Platform admins need to understand Omni Access Policies

### Neutral

- **Access Policy YAML format**: Currently uses direct user lists in rules (usergroups/clustergroups syntax appeared unsupported or undocumented)
- **Role assignment**: Using `role: Reader` to enable self-service kubeconfig download

## Related Decisions

- [ADR-002: Group-Based RBAC Over Individual User Bindings](002-group-based-rbac-over-individual-user-bindings.md)
- [ADR-003: Accept Read Visibility in Exchange for Write Isolation](003-accept-read-visibility-in-exchange-for-write-isolation.md)

## References

- [docs/access-policies-reference.md](../access-policies-reference.md) - Complete Omni ACL guide
- [docs/adding-users.md](../adding-users.md) - User onboarding workflow
- [docs/omni-access-policy.yaml](../omni-access-policy.yaml) - Current Access Policy configuration
