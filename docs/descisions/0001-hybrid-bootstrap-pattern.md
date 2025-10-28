# Hybrid Bootstrap Pattern (Inline Manifests + GitOps)

## Context and Problem Statement

Bootstrapping a Kubernetes cluster managed by Omni presents a chicken-and-egg problem: ArgoCD needs networking to pull manifests from Git, networking (CNI) requires cluster initialization, but manual application of CNI and ArgoCD is error-prone and not reproducible. How can we achieve fully automated, reproducible cluster bootstrap?

## Decision Drivers

* Need for zero manual kubectl commands after cluster creation
* Omni's cluster template system supports inline manifests embedded in machine config
* Desire for GitOps as the single source of truth
* Requirement for reproducible cluster rebuilds
* Challenge of maintaining embedded YAML manifests

## Considered Options

* Pure inline manifests (all components embedded in patches)
* Manual bootstrap (manually apply CNI and ArgoCD via kubectl)
* Helm Operator bootstrap (use Flux/Helm Operator)
* Hybrid pattern (inline bootstrap + GitOps takeover)

## Decision Outcome

Chosen option: "Hybrid pattern (inline bootstrap + GitOps takeover)", because it provides zero-touch bootstrap while maintaining GitOps as the single source of truth after cluster initialization.

We will use a **two-phase hybrid bootstrap pattern**:

### Phase 1: Inline Bootstrap (Omni Patches)

Deploy minimal components inline to enable cluster functionality:

1. **Cilium CNI** (`bootstrap/talos/patches/cilium.yaml`)
   - Embedded in machine config
   - Enables pod networking immediately on cluster creation
   - Required for any pod-to-pod communication

2. **ArgoCD** (`bootstrap/talos/patches/argocd.yaml`)
   - Minimal deployment (server, repo-server, application-controller)
   - Enables GitOps from day one
   - Applied before any other workloads

**Regeneration workflow:**
```bash
# After modifying apps/kube-system/cilium/
kustomize build apps/kube-system/cilium | \
  yq -i 'with(.cluster.inlineManifests.[] | select(.name=="cilium"); .contents=load_str("/dev/stdin"))' \
  bootstrap/talos/patches/cilium.yaml

# After modifying apps/argocd/argocd/
kustomize build apps/argocd/argocd | \
  yq -i 'with(.cluster.inlineManifests.[] | select(.name=="argocd"); .contents=load_str("/dev/stdin"))' \
  bootstrap/talos/patches/argocd.yaml
```

### Phase 2: ArgoCD Takeover (GitOps)

ArgoCD manages itself and all other components:

1. **Self-management**: ArgoCD adopts its own inline-deployed resources
   - Uses `ServerSideApply` to take ownership without downtime
   - `ignoreDifferences` for dynamically generated fields (certs, runtime config)

2. **Sync waves**: Ordered deployment of dependent resources
   - Wave -2: Namespaces
   - Wave -1: Vault, Cilium (handover from inline)
   - Wave 0: External Secrets, cert-manager, Longhorn
   - Wave 1: Monitoring (requires storage)

3. **Continuous sync**: Git becomes single source of truth
   - Changes applied via git push → ArgoCD auto-sync
   - Drift detection and auto-correction

## Consequences

### Positive

- **Reproducible**: Cluster bootstrap is fully automated
- **Self-healing**: ArgoCD corrects configuration drift
- **No manual steps**: Zero kubectl commands needed after cluster creation
- **GitOps from day one**: All changes tracked in Git
- **Seamless handover**: Inline resources adopted without downtime
- **Version controlled**: Inline manifests regenerated from GitOps sources

### Negative

- **Two sources of truth during bootstrap**: Inline patches + Git repo
- **Regeneration required**: Changes to Cilium/ArgoCD need patch regeneration
- **Complexity**: Developers must understand the handover mechanism
- **Initial learning curve**: `ignoreDifferences` and `ServerSideApply` nuances

### Neutral

- **Taskfile automation**: `task regenerate:cilium` and `task regenerate:argocd` simplify workflow
- **Documentation requirement**: Bootstrap pattern must be clearly documented

## Alternatives Considered

### Alternative 1: Pure Inline Manifests
**Rejected**: All components embedded in patches
- **Problem**: Extremely difficult to maintain and version
- **Problem**: No GitOps workflow

### Alternative 2: Manual Bootstrap
**Rejected**: Manually apply CNI and ArgoCD via kubectl
- **Problem**: Not reproducible
- **Problem**: Requires manual intervention on every cluster rebuild

### Alternative 3: Helm Operator Bootstrap
**Rejected**: Use Flux/Helm Operator for bootstrap
- **Problem**: Adds another tool to the stack
- **Problem**: Omni doesn't natively support Flux bootstrap

## Related Decisions

- [ADR-006: ArgoCD Sync Waves for Bootstrap Ordering](006-argocd-sync-waves-for-bootstrap-ordering.md)
- Bootstrap pattern influenced by Talos Linux immutable OS design

## References

- [bootstrap/talos/patches/cilium.yaml](../../bootstrap/talos/patches/cilium.yaml)
- [bootstrap/talos/patches/argocd.yaml](../../bootstrap/talos/patches/argocd.yaml)
- [Taskfile.yml](../../Taskfile.yml) - Regeneration tasks
- [CLAUDE.md](../../CLAUDE.md) - Bootstrap pattern documentation
