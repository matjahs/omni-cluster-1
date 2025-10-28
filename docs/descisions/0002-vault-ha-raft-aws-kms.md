# ADR-002: Vault HA with Raft Storage and AWS KMS Auto-Unseal

**Status:** Accepted

**Date:** 2025-10-19 (Raft), 2025-10-21 (AWS KMS)

**Deciders:** Platform Team

## Context

The cluster requires a secrets management solution for:
- ArgoCD credentials (admin password, server secret key)
- Application secrets (database passwords, API keys)
- Tenant-specific secrets (via External Secrets Operator)

Initial Vault deployment used:
- **Single standalone instance** (non-HA)
- **File storage backend** (not suitable for HA)
- **Manual unseal** (required operator intervention after restarts)

Production requirements:
1. **High availability**: Vault should survive pod failures
2. **Zero-downtime**: No manual unseal after restarts
3. **Persistent storage**: Secrets must survive cluster rebuilds
4. **Kubernetes-native**: Leverage K8s StatefulSet and Services

## Decision

We will deploy **Vault in HA mode** with:

### 1. Raft Integrated Storage

**Configuration:**
```yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      config: |
        storage "raft" {
          path = "/vault/data"
        }
        service_registration "kubernetes" {}
```

**Why Raft:**
- **No external dependencies**: Embedded storage, no Consul/etcd required
- **Strongly consistent**: Built-in leader election and data replication
- **Kubernetes-native**: Uses StatefulSet with persistent volumes
- **Simple operations**: Join nodes via `vault operator raft join`

**Storage:**
- 10Gi PersistentVolume per replica (Longhorn StorageClass)
- `/vault/data` mounted in each pod
- Automatic replication across 3 nodes

### 2. AWS KMS Auto-Unseal

**Configuration:**
```yaml
seal "awskms" {
  region     = "eu-central-1"
  kms_key_id = "ba4a546a-bcd3-49e6-8a41-5ed55a3e407c"
}

extraSecretEnvironmentVars:
  - envName: AWS_ACCESS_KEY_ID
    secretName: vault-kms-creds
    secretKey: access_key
  - envName: AWS_SECRET_ACCESS_KEY
    secretName: vault-kms-creds
    secretKey: secret_key
```

**Why AWS KMS:**
- **Zero-touch unsealing**: Pods auto-unseal on startup
- **No unseal keys to manage**: Root key encrypted by AWS KMS
- **Security compliance**: Keys stored in HSM-backed service
- **Disaster recovery**: Simplified backup/restore (no key shards)

**Secret management:**
- AWS credentials stored in Kubernetes Secret `vault-kms-creds`
- IAM policy allows `kms:Decrypt` and `kms:Encrypt` only
- KMS key in `eu-central-1` (same region as cluster for low latency)

### 3. Deployment Architecture

```
┌─────────────────────────────────────────┐
│      vault-ha-active (ClusterIP)       │  ← External Secrets Operator
│      Points to active/leader pod        │
└─────────────────────────────────────────┘
                    │
    ┌───────────────┼───────────────┐
    ↓               ↓               ↓
┌──────────┐  ┌──────────┐  ┌──────────┐
│ vault-ha-0│  │ vault-ha-1│  │ vault-ha-2│
│  (leader) │  │ (standby) │  │ (standby) │
│           │  │           │  │           │
│  PV: 10Gi │  │  PV: 10Gi │  │  PV: 10Gi │
└──────────┘  └──────────┘  └──────────┘
     │              │              │
     └──────────────┴──────────────┘
              Raft Cluster
         (3-way replication)
```

### 4. Initialization Workflow

**One-time setup:**
```bash
# 1. Initialize Vault (generates root token, no unseal keys)
kubectl exec -n vault vault-ha-0 -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json

# 2. Join standby nodes to Raft cluster
kubectl exec -n vault vault-ha-1 -- \
  vault operator raft join http://vault-ha-0.vault-ha-internal:8200
kubectl exec -n vault vault-ha-2 -- \
  vault operator raft join http://vault-ha-0.vault-ha-internal:8200

# 3. Configure Kubernetes auth and policies
# (See scripts in apps/vault/scripts/)
```

**After pod restart:**
- Pods automatically unseal via AWS KMS
- Standby nodes rejoin Raft cluster
- No manual intervention required

## Consequences

### Positive

- **High availability**: Survives single-node failures
- **Zero manual unseal**: Pods restart without operator intervention
- **Strongly consistent**: Raft guarantees leader election and replication
- **Simple architecture**: No external Consul/etcd dependencies
- **Disaster recovery**: Simplified backup (just PVs + KMS key access)
- **Kubernetes-native**: Uses StatefulSet, headless Service, PVs

### Negative

- **AWS dependency**: Requires AWS KMS and credentials
- **Cost**: AWS KMS key + API calls (minimal: ~$1/month + $0.03/10k requests)
- **Initial complexity**: Raft cluster formation requires manual join
- **Storage overhead**: 3x data replication (30Gi total for 10Gi)

### Neutral

- **eu-central-1 region**: Hardcoded for low-latency KMS access
- **TLS disabled**: Using `tls_disable = 1` for cluster-internal traffic (acceptable for dev/test, should enable for prod)
- **3 replicas**: Tolerates 1 node failure (quorum: 2/3). Could use 5 replicas for 2-node failure tolerance.

## Alternatives Considered

### Alternative 1: Consul Storage Backend
**Rejected**: Requires separate Consul cluster
- **Problem**: Additional operational complexity
- **Problem**: Consul requires its own HA setup

### Alternative 2: Manual Unseal with Shamir Keys
**Rejected**: Requires operator intervention
- **Problem**: Pods can't auto-restart without human
- **Problem**: Unseal keys must be stored securely (key management burden)

### Alternative 3: Transit Auto-Unseal (Vault-to-Vault)
**Rejected**: Requires separate Vault cluster
- **Problem**: Chicken-and-egg problem
- **Problem**: Doesn't eliminate manual unseal for root Vault

### Alternative 4: Kubernetes Secret Auto-Unseal
**Considered**: Store master key in K8s Secret
- **Problem**: Not available in Hashicorp Vault (only in Vault Enterprise)
- **Security concern**: Root key in plaintext K8s secret

## Related Decisions

- [ADR-005: External Secrets Operator for Vault Integration](005-external-secrets-operator-for-vault-integration.md)
- [ADR-004: Longhorn on Talos STATE Partition](004-longhorn-on-talos-state-partition.md) - Provides PVs for Raft storage
- [ADR-006: ArgoCD Sync Waves for Bootstrap Ordering](006-argocd-sync-waves-for-bootstrap-ordering.md) - Vault in Wave -1

## References

- [Vault Raft Storage Documentation](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [Vault AWS KMS Auto-Unseal](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms)
- Commits: [9498923](../../.git) (Raft), [a06d0f4](../../.git) (AWS KMS)
