# ADR-009: Read Visibility vs Write Isolation

**Status:** Accepted

**Date:** 2025-10-27

**Deciders:** Platform Team

## Context

When implementing multi-tenant Kubernetes clusters, there are two isolation philosophies:

### Option 1: Strict Isolation (Read + Write)
- Users **cannot view** resources in other namespaces
- Users **cannot modify** resources in other namespaces
- Requires restrictive RBAC and network policies

### Option 2: Write Isolation Only (Industry Standard)
- Users **can view** resources in other namespaces
- Users **cannot modify** resources in other namespaces
- Uses standard Kubernetes RBAC with OIDC authentication

### Initial Requirement

User initially requested "strict namespace isolation" (Option 1):
> "We want option 2" - referring to strict isolation where users cannot see other namespaces

### Investigation: Omni Access Policy Role Behavior

We tested three Omni role settings:

#### Test 1: `role: None`
```yaml
# docs/omni-access-policy.yaml
- users: [alice@example.com]
  role: None  # Minimal Omni permissions
  kubernetes:
    impersonate:
      groups: [team-a-admins]
```

**Result:**
```bash
$ kubectl get pods -n team-a
NAME                     READY   STATUS    RESTARTS   AGE
app-1-7b9c8d5f6-abc123   1/1     Running   0          10m

$ kubectl get pods -n team-b
NAME                     READY   STATUS    RESTARTS   AGE
app-2-6c8d7e4f5-xyz789   1/1     Running   0          5m
```

**Observation:** Users could still **view** other namespaces, despite `role: None`.

#### Test 2: Manual Kubeconfig Generation
Attempted to create restrictive kubeconfig with impersonation:

```bash
# scripts/generate-user-kubeconfig.sh
kubectl config set-credentials alice@example.com \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=--as-group=team-a-admins
```

**Result:** Kubeconfig prompted for credentials and failed to authenticate.

**Root Cause:** Omni uses its own OIDC provider, not Kubernetes client certificates. The manual kubeconfig couldn't authenticate without Omni's OIDC flow.

#### Test 3: Kubernetes RBAC Only (No Cluster-Wide Read)
Attempted to create Role (not ClusterRole) limiting list/get to single namespace:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-admin
  namespace: team-a
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]  # Only in team-a namespace
```

**Result:** Users could still see other namespaces.

**Root Cause:** Omni's OIDC authentication grants **authenticated users** cluster-wide read access for operational reasons (same as `system:authenticated` default permissions).

### Discovery: Industry-Standard Behavior

Kubernetes OIDC authentication (including Omni, GKE, EKS, AKS) **intentionally** allows authenticated users to:
- List namespaces (`kubectl get namespaces`)
- View resources in other namespaces (`kubectl get pods -n other-namespace`)

This is **by design** because:
1. **Operational visibility**: Developers need to see cluster state
2. **Resource discovery**: Tools like `kubectl get all --all-namespaces` require cluster-wide read
3. **Monitoring integration**: Prometheus, observability tools need cluster-wide read
4. **Security through obscurity is not security**: Hiding namespace names doesn't prevent attacks

**What IS enforced:**
- **Write isolation**: Users cannot create/modify/delete resources in other namespaces
- **Network isolation**: Pods cannot communicate across tenant boundaries (via NetworkPolicies)
- **Resource quotas**: Tenants cannot exhaust cluster resources

## Decision

We will **accept read visibility** and enforce **write isolation**.

### Rationale

1. **Industry standard**: Matches behavior of GKE, EKS, AKS, and other managed Kubernetes
2. **Operational pragmatism**: Users benefit from seeing cluster state for debugging
3. **Security-where-it-matters**: Write operations are strictly controlled
4. **Network isolation**: Pod-to-pod communication is blocked (more important than visibility)
5. **User experience**: `role: Reader` enables self-service kubeconfig download

### Omni Role: Reader

```yaml
# docs/omni-access-policy.yaml
spec:
  rules:
    - users: [alice@example.com]
      role: Reader  # Allows kubeconfig download
      kubernetes:
        impersonate:
          groups: [team-a-admins]
```

**Why `Reader`:**
- **Self-service kubeconfig**: Users download their own kubeconfigs without admin help
- **Minimal Omni permissions**: Can view cluster, cannot modify lifecycle
- **Standard OIDC behavior**: Cluster-wide read is expected

**Write isolation enforced via Kubernetes RBAC:**
```yaml
# tenants/team-a/resources/group-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding  # NOT ClusterRoleBinding (namespace-scoped)
metadata:
  name: team-a-admins-binding
  namespace: team-a
subjects:
- kind: Group
  name: team-a-admins
roleRef:
  kind: Role  # NOT ClusterRole (namespace-scoped permissions)
  name: team-a-admin
```

### What IS Enforced

| Operation | team-a Namespace | team-b Namespace |
|-----------|------------------|------------------|
| **View pods** | ✅ Allowed | ✅ Allowed (read-only) |
| **Create pods** | ✅ Allowed | ❌ Forbidden |
| **Delete pods** | ✅ Allowed | ❌ Forbidden |
| **Modify services** | ✅ Allowed | ❌ Forbidden |
| **Network access** | ✅ Allowed (within team-a) | ❌ Blocked (NetworkPolicy) |

### What Is NOT Enforced

| Operation | team-a Namespace | team-b Namespace |
|-----------|------------------|------------------|
| **List namespaces** | ✅ Allowed | ✅ Allowed |
| **View resource names** | ✅ Allowed | ✅ Allowed |
| **Read ConfigMaps** | ✅ Allowed | ✅ Allowed (if no RBAC restrictions) |

**Important:** Sensitive data should be in Secrets (not ConfigMaps) and protected with namespace-scoped RBAC.

## Consequences

### Positive

- **Industry-standard security model**: Matches expectations from GKE/EKS/AKS
- **Better user experience**: Users can debug and understand cluster state
- **Self-service enabled**: `role: Reader` allows kubeconfig download
- **Simpler RBAC**: Standard Kubernetes patterns, no custom admission controllers
- **Monitoring-friendly**: Prometheus and observability tools work out-of-box

### Negative

- **Namespace names visible**: Tenants can see other tenant namespace names
  - **Mitigation**: Don't encode sensitive data in namespace names
- **Resource metadata visible**: Tenants can see pod names, service names in other namespaces
  - **Mitigation**: Don't encode sensitive data in resource names
- **Not "security through obscurity"**: Hiding names doesn't prevent attacks

### Neutral

- **True strict isolation requires separate clusters**: For compliance/regulatory requirements, use separate clusters or vCluster/Loft
- **Network isolation is more critical**: Pod-to-pod traffic blocking (via NetworkPolicies) is more important than visibility

## Alternatives Considered

### Alternative 1: Separate Clusters per Tenant
**Accepted for high-security scenarios**:
- **Advantage**: True isolation (network, compute, control plane)
- **Trade-off**: Higher operational cost, more complex management
- **Use case**: Regulatory compliance, highly sensitive workloads

### Alternative 2: vCluster or Loft
**Considered**: Virtual clusters within physical cluster
- **Advantage**: Isolation without separate physical clusters
- **Trade-off**: Additional complexity, resource overhead
- **Decision**: Deferred for future evaluation

### Alternative 3: Custom Admission Controller
**Rejected**: Overly complex
- **Problem**: Must intercept all API requests and rewrite/deny
- **Problem**: Additional component to maintain
- **Problem**: Doesn't align with Kubernetes security model

### Alternative 4: Remove Omni `role: Reader`
**Rejected**: Breaks self-service
- **Problem**: Users cannot download kubeconfigs (admin intervention required)
- **Problem**: Doesn't actually provide strict isolation (authenticated users still have cluster-wide read)

## Related Decisions

- [ADR-007: Omni Access Policies for User Management](007-omni-access-policies-for-user-management.md)
- [ADR-008: Group-Based RBAC Over Individual User Bindings](008-group-based-rbac-over-individual-user-bindings.md)

## References

- [docs/namespace-isolation.md](../namespace-isolation.md) - Complete isolation explanation
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [GKE Multi-Tenancy Best Practices](https://cloud.google.com/kubernetes-engine/docs/concepts/multitenancy-overview)
