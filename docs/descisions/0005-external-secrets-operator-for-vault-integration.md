# ADR-005: External Secrets Operator for Vault Integration

**Status:** Accepted

**Date:** 2025-10-18

**Deciders:** Platform Team

## Context

Kubernetes applications require secrets (passwords, API keys, certificates) that should:
- **Not be committed to Git** (security risk)
- **Be centrally managed** (single source of truth)
- **Be rotated regularly** (security best practice)
- **Be audited** (compliance requirement)

Vault is deployed for centralized secrets management, but Kubernetes workloads need secrets as K8s Secret resources.

Traditional approaches:
1. **Manual kubectl commands**: Create secrets via `kubectl create secret`
   - Problem: Not GitOps-friendly, no version control
   - Problem: Secrets must be manually updated when rotated

2. **Sealed Secrets**: Encrypt secrets in Git
   - Problem: Still stored in Git (encrypted but present)
   - Problem: Difficult key rotation

3. **Vault Agent Sidecar**: Inject secrets into pods
   - Problem: Requires sidecar per pod (resource overhead)
   - Problem: Application must read from filesystem

4. **External Secrets Operator**: Sync Vault secrets to K8s Secrets
   - Solution: Declarative, GitOps-friendly
   - Solution: Automatic sync and rotation

## Decision

We will use **External Secrets Operator (ESO)** to sync Vault secrets into Kubernetes Secret resources.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  Vault (vault namespace)                        │
│  - Centralized secrets storage                  │
│  - Kubernetes auth enabled                      │
└──────────────────┬──────────────────────────────┘
                   │
                   │ (Kubernetes token auth)
                   ↓
┌─────────────────────────────────────────────────┐
│  External Secrets Operator                      │
│  - Watches ExternalSecret resources             │
│  - Authenticates to Vault                       │
│  - Syncs secrets to K8s                         │
└──────────────────┬──────────────────────────────┘
                   │
    ┌──────────────┴──────────────┐
    │                             │
    ↓                             ↓
┌─────────────────┐     ┌─────────────────┐
│ ExternalSecret  │     │ ExternalSecret  │
│ (argocd ns)     │     │ (team-a ns)     │
│                 │     │                 │
│ References:     │     │ References:     │
│ - SecretStore   │     │ - SecretStore   │
│ - Vault path    │     │ - Vault path    │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ↓                       ↓
┌─────────────────┐     ┌─────────────────┐
│ K8s Secret      │     │ K8s Secret      │
│ (auto-created)  │     │ (auto-created)  │
└─────────────────┘     └─────────────────┘
```

### Configuration

#### 1. Deploy External Secrets Operator

```yaml
# apps/external-secrets/external-secrets-operator/Chart.yaml
dependencies:
  - name: external-secrets
    version: 0.20.3
    repository: https://charts.external-secrets.io
```

#### 2. Create ClusterSecretStore (Cluster-Wide)

```yaml
# apps/external-secrets/external-secrets-operator-config/cluster-secretstore.yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-cluster-store
spec:
  provider:
    vault:
      server: "http://vault-ha.vault:8200"
      path: kv
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: external-secrets
          serviceAccountRef:
            name: external-secrets-operator
            namespace: external-secrets
```

**ClusterSecretStore advantages:**
- Used by any namespace
- Single Vault authentication configuration
- No per-namespace SecretStore duplication

#### 3. Configure Vault Kubernetes Auth

```bash
# Enable Kubernetes auth in Vault
vault auth enable kubernetes

# Configure Kubernetes API endpoint
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Create policy for External Secrets Operator
vault policy write external-secrets-reader - <<EOF
path "kv/data/argocd/*" {
  capabilities = ["read"]
}
path "kv/data/team-a/*" {
  capabilities = ["read"]
}
EOF

# Create role binding service account to policy
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names="external-secrets-operator" \
  bound_service_account_namespaces="external-secrets" \
  policies="external-secrets-reader" \
  ttl="24h"
```

#### 4. Create ExternalSecret Resources

```yaml
# apps/argocd/argocd/argocd-external-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-cluster-store
    kind: ClusterSecretStore
  target:
    name: argocd-secret
    creationPolicy: Owner
  data:
    - secretKey: server.secretkey
      remoteRef:
        key: kv/argocd/admin
        property: server.secretkey
    - secretKey: admin.password
      remoteRef:
        key: kv/argocd/admin
        property: admin.password
    - secretKey: admin.passwordMtime
      remoteRef:
        key: kv/argocd/admin
        property: admin.passwordMtime
```

**How it works:**
1. ESO reads `ExternalSecret` resource
2. Authenticates to Vault using service account token
3. Fetches secrets from `kv/argocd/admin` path
4. Creates/updates K8s Secret `argocd-secret`
5. Automatically refreshes every hour

### Secrets in Git (GitOps Pattern)

**What's in Git:**
- `ExternalSecret` resource (references Vault paths)
- `ClusterSecretStore` configuration (Vault connection)

**What's NOT in Git:**
- Actual secret values (stored in Vault only)
- K8s Secret resources (generated by ESO)

## Consequences

### Positive

- **GitOps-friendly**: ExternalSecret resources committed to Git
- **No secrets in Git**: Actual values stay in Vault
- **Automatic sync**: ESO updates K8s Secrets when Vault changes
- **Centralized management**: Single Vault instance for all secrets
- **Rotation support**: Change in Vault propagates to K8s (within refresh interval)
- **Audit trail**: Vault logs all secret access
- **Namespace isolation**: RBAC controls which namespaces access which secrets

### Negative

- **Additional component**: ESO operator must be deployed and maintained
- **Vault dependency**: K8s secrets unavailable if Vault is down
  - **Mitigation**: ESO caches secrets, existing K8s Secrets remain
- **Sync delay**: Secrets updated every `refreshInterval` (default: 1h)
  - **Mitigation**: Can force immediate sync or reduce interval
- **Complexity**: Teams must understand Vault paths and ExternalSecret syntax

### Neutral

- **Bootstrap chicken-and-egg**: ESO needs Vault, Vault needs ESO for some configs
  - **Solution**: Deploy Vault first (Wave -1), ESO in Wave 0
- **Kubernetes auth**: Requires ClusterRoleBinding for Vault token review

## Alternatives Considered

### Alternative 1: Manual kubectl create secret
**Rejected**: Not GitOps-friendly
- **Problem**: Secrets not version-controlled
- **Problem**: Manual updates required

### Alternative 2: Sealed Secrets
**Rejected**: Secrets still in Git (encrypted)
- **Problem**: Key rotation is complex
- **Problem**: Sealed Secret controller is single point of failure

### Alternative 3: Vault Agent Sidecar
**Rejected**: Per-pod overhead
- **Problem**: Resource usage (sidecar per pod)
- **Problem**: Application must read from filesystem (not K8s Secret)

### Alternative 4: Vault CSI Provider
**Considered**: Similar to Vault Agent
- **Problem**: Requires CSI driver (additional complexity)
- **Problem**: Secrets as volumes, not K8s Secrets

## Related Decisions

- [ADR-002: Vault HA with Raft Storage and AWS KMS Auto-Unseal](002-vault-ha-raft-aws-kms.md)
- [ADR-006: ArgoCD Sync Waves for Bootstrap Ordering](006-argocd-sync-waves-for-bootstrap-ordering.md) - ESO in Wave 0

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [apps/external-secrets/](../../apps/external-secrets)
- Commits: [8498c5b](../../.git), [260b851](../../.git), [efb657f](../../.git)
