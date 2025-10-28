# ADR-006: ArgoCD Sync Waves for Bootstrap Ordering

**Status:** Accepted

**Date:** 2025-10-18

**Deciders:** Platform Team

## Context

After the hybrid bootstrap (inline Cilium + ArgoCD), ArgoCD must manage all cluster components. However, components have dependencies:

**Dependency chains:**
- **Monitoring** requires **Longhorn** (for Prometheus persistent volumes)
- **Applications** require **External Secrets** (for secrets)
- **External Secrets** requires **Vault** (for secret backend)
- **Vault** requires **namespace** (for deployment)
- **All workloads** require **Cilium** (for networking)

Without ordering:
- ArgoCD may deploy Prometheus before Longhorn (PVC pending)
- External Secrets may start before Vault is ready (auth failures)
- Applications may fail due to missing secrets

Traditional solutions:
1. **Manual ordering**: Deploy components one by one
   - Problem: Not GitOps, requires manual intervention
2. **Health checks + retries**: Let ArgoCD retry failures
   - Problem: Slow, generates error events
3. **Application dependencies**: Use `dependsOn` in Application specs
   - Problem: Verbose, must specify for every app

ArgoCD provides **Sync Waves**: Numeric annotations that control deployment order.

## Decision

We will use **ArgoCD Sync Waves** to enforce bootstrap ordering.

### Sync Wave Strategy

```
Wave -2: Namespaces (foundational)
  ├─ kube-system namespace

Wave -1: Core Infrastructure (networking + handover)
  ├─ Cilium (handover from inline)
  └─ Vault (secrets backend)

Wave 0: Platform Services (secrets, storage, monitoring)
  ├─ External Secrets Operator
  ├─ cert-manager
  ├─ Longhorn (storage)
  ├─ Monitoring namespaces
  └─ Application namespaces (argocd, monitoring, longhorn-system)

Wave 1: Management & Observability
  ├─ ArgoCD (self-management)
  ├─ Prometheus/Grafana (requires Longhorn PVs)
  └─ Configuration (HTTPRoutes, L2 policies)
```

### Implementation

#### 1. ApplicationSet with Sync Wave Templating

```yaml
# apps/argocd/argocd/bootstrap-app-set.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: bootstrap
spec:
  generators:
    - git:
        files:
          - path: "apps/*/*/metadata.yaml"
  template:
    metadata:
      annotations:
        argocd.argoproj.io/sync-wave: "{{ syncWave }}"
    spec:
      syncPolicy:
        automated:
          prune: false
        syncOptions:
          - ServerSideApply=true
          - RespectIgnoreDifferences=true
        retry:
          limit: -1  # Infinite retries for transient failures
```

**How it works:**
1. ApplicationSet scans `apps/*/*/metadata.yaml` files
2. Extracts `syncWave` value from each metadata file
3. Creates Application with `sync-wave` annotation
4. ArgoCD processes waves sequentially: -2, -1, 0, 1, ...

#### 2. Per-Application Metadata Files

```yaml
# apps/kube-system/namespace/metadata.yaml
name: cilium-namespace
syncWave: "-2"
namespace: kube-system
appPath: apps/kube-system/namespace
```

```yaml
# apps/kube-system/cilium/metadata.yaml
name: cilium-chart
syncWave: "-1"
namespace: kube-system
appPath: apps/kube-system/cilium
```

```yaml
# apps/vault/vault/metadata.yaml
name: vault
syncWave: "-1"
namespace: vault
appPath: apps/vault/vault
```

```yaml
# apps/external-secrets/external-secrets-operator/metadata.yaml
name: external-secrets-operator
syncWave: "0"
namespace: external-secrets
appPath: apps/external-secrets/external-secrets-operator
```

```yaml
# apps/monitoring/kube-prometheus-stack/metadata.yaml
name: kube-prometheus-stack
syncWave: "1"
namespace: monitoring
appPath: apps/monitoring/kube-prometheus-stack
```

### Special Considerations

#### Cilium Handover (Wave -1)

Cilium is deployed inline during bootstrap, then ArgoCD adopts it:

```yaml
syncOptions:
  - ServerSideApply=true       # Adopt existing resources
  - RespectIgnoreDifferences=true

ignoreDifferences:
  - group: apps
    kind: DaemonSet
    name: cilium
    jsonPointers:
      - /spec/template/metadata/annotations/ca-certificates
      - /status
```

**ServerSideApply**: Allows ArgoCD to take ownership without replacing existing resources.

#### Vault Bootstrap (Wave -1)

Vault requires manual initialization (one-time):
```bash
# After Vault deploys
kubectl exec vault-ha-0 -- vault operator init
kubectl exec vault-ha-1 -- vault operator raft join http://vault-ha-0:8200
```

**Future improvement**: Vault bootstrap job could automate this.

## Consequences

### Positive

- **Deterministic ordering**: Components deploy in predictable sequence
- **Reduced errors**: Dependencies available before dependent apps start
- **Fast deployment**: No manual waiting between waves
- **Self-documenting**: Sync wave numbers show dependency hierarchy
- **Automatic retries**: Failed deployments retry until success (`limit: -1`)
- **GitOps-friendly**: Ordering defined in metadata files

### Negative

- **Sequential deployment**: Cannot parallelize within dependencies
  - **Impact**: Longer initial bootstrap time (~5-10 minutes)
- **Metadata file proliferation**: Each app needs metadata.yaml
- **Wave number management**: Must coordinate wave numbers across team
- **Debugging complexity**: Failed wave blocks subsequent waves

### Neutral

- **Wave granularity**: Using coarse waves (-2, -1, 0, 1) vs fine-grained (0-20)
  - **Decision**: Coarse is sufficient, easier to understand
- **Infinite retries**: `limit: -1` means failed apps retry forever
  - **Trade-off**: Prevents boot-loop but may hide issues

## Alternatives Considered

### Alternative 1: Manual Sequential Deployment
**Rejected**: Not GitOps
- **Problem**: Requires operator to deploy in order
- **Problem**: Difficult to reproduce

### Alternative 2: Application Dependencies (dependsOn)
**Rejected**: Too verbose
- **Problem**: Must specify dependencies for every app
- **Problem**: Doesn't support transitive dependencies well

### Alternative 3: Health Checks + Retry Backoff
**Rejected**: Slow and noisy
- **Problem**: Apps fail and retry for minutes
- **Problem**: Generates error events and alerts

### Alternative 4: Helm Hooks
**Rejected**: Only works within single Helm chart
- **Problem**: Can't order across multiple applications
- **Problem**: Tied to Helm (not kustomize-friendly)

## Related Decisions

- [ADR-001: Hybrid Bootstrap Pattern](001-hybrid-bootstrap-pattern.md) - Inline manifests lead to sync waves
- [ADR-002: Vault HA with Raft Storage](002-vault-ha-raft-aws-kms.md) - Vault in Wave -1
- [ADR-004: Longhorn on Talos STATE Partition](004-longhorn-on-talos-state-partition.md) - Longhorn in Wave 0
- [ADR-005: External Secrets Operator](005-external-secrets-operator-for-vault-integration.md) - ESO in Wave 0

## References

- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [apps/argocd/argocd/bootstrap-app-set.yaml](../../apps/argocd/argocd/bootstrap-app-set.yaml)
- [apps/*/*/metadata.yaml](../../apps) - Sync wave definitions
- Commit: [ac19e34](../../.git)
