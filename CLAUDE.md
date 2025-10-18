# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository manages a **Talos Kubernetes cluster** deployed via **Sidero Labs Omni**. It uses a GitOps approach with **ArgoCD** for application management and implements a multi-tenant architecture.

**Key Technologies:**
- **Omni**: Cluster lifecycle management (via `omnictl`)
- **Talos Linux**: Immutable Kubernetes OS
- **ArgoCD**: GitOps continuous delivery
- **Cilium**: CNI with Gateway API support
- **Longhorn**: Persistent storage
- **Vault**: Secrets management
- **Prometheus/Grafana**: Monitoring stack

## Repository Structure

```
omni-cluster-1/
├── infra/                          # Omni cluster definition
│   ├── cluster-template.yaml       # Main cluster spec (Talos/K8s versions, features)
│   └── patches/                    # Machine config patches
│       ├── argocd.yaml            # ArgoCD bootstrap inline manifest
│       ├── cilium.yaml            # Cilium bootstrap inline manifest
│       ├── cni.yaml               # CNI configuration
│       ├── user-volume.yaml       # Longhorn storage mounts
│       └── ...
├── argocd/                         # ArgoCD application definitions
│   ├── apps/                       # Infrastructure apps (per-namespace/app structure)
│   │   ├── argocd/argocd/         # ArgoCD self-management
│   │   ├── kube-system/cilium/    # Cilium (managed by ArgoCD after bootstrap)
│   │   ├── longhorn-system/longhorn/
│   │   ├── monitoring/kube-prometheus-stack/
│   │   └── vault/vault/
│   ├── projects/                   # ArgoCD AppProjects
│   │   └── tenants-projects.yaml  # Tenant governance boundaries
│   └── apps/
│       ├── tenant-appset.yaml      # Tenant ApplicationSet
│       └── infra.yaml              # Infrastructure apps (cert-manager, ingress-nginx)
├── helm/                           # Local Helm charts
│   └── tenant-baseline/            # Multi-tenant baseline chart
│       ├── Chart.yaml
│       ├── values.yaml             # Default RBAC, quotas, network policies
│       └── templates/
└── tenants/                        # Tenant-specific configurations
    ├── team-a/
    │   ├── tenant.values.yaml      # Overrides for tenant-baseline chart
    │   └── resources/              # Optional tenant workloads
    └── team-b/
```

## Common Commands

### Cluster Management

```bash
# Deploy/update cluster configuration
cd infra
omnictl cluster template sync --file cluster-template.yaml

# Check cluster status
omnictl cluster status talos-default

# Get kubeconfig
omnictl kubeconfig talos-default > ~/.kube/config-omni
```

### ArgoCD Operations

```bash
# Access ArgoCD UI (via Omni Workload Proxy)
# URL is shown in Omni console after deployment

# Sync all applications
kubectl -n argocd get applications
argocd app sync --async --prune <app-name>

# Force refresh application
argocd app get <app-name> --refresh
```

### Helm Chart Development

```bash
# Update Helm chart dependencies (for apps using local charts)
cd argocd/apps/<namespace>/<app-name>
helm dependency update

# Test Helm template rendering
helm template my-release . --values values.yaml

# Lint tenant baseline chart
cd helm/tenant-baseline
helm lint .
```

### Application Regeneration

When modifying ArgoCD's self-managed configuration:

```bash
# Regenerate argocd.yaml patch after modifying argocd/apps/argocd/argocd/
kustomize build argocd/apps/argocd/argocd | \
  yq -i 'with(.cluster.inlineManifests.[] | select(.name=="argocd"); .contents=load_str("/dev/stdin"))' \
  infra/patches/argocd.yaml
```

## Architecture Patterns

### Bootstrap Pattern: Hybrid Inline + GitOps

This cluster uses a **two-phase bootstrap** to solve the chicken-and-egg problem:

**Phase 1: Inline Manifests (Omni patches)**
- **Cilium CNI**: Deployed inline to enable pod networking immediately
- **ArgoCD**: Deployed inline to enable GitOps from cluster creation

These are embedded in `infra/patches/cilium.yaml` and `infra/patches/argocd.yaml`.

**Phase 2: ArgoCD Management**
After bootstrap, ArgoCD takes over via sync waves:
- **Wave -2**: Vault namespace
- **Wave -1**: Vault, Cilium (handover from inline)
  - Uses `ServerSideApply` to adopt existing Cilium resources
  - `ignoreDifferences` for dynamically generated certs/runtime fields
- **Wave 0**: Longhorn storage, namespaces
- **Wave 1**: Monitoring stack (requires persistent storage)

Sync waves are defined in `argocd/apps/argocd/argocd/bootstrap-app-set.yaml`.

### Multi-Tenant Pattern

Tenants are managed via ArgoCD ApplicationSet (`argocd/apps/tenant-appset.yaml`):

1. **Directory-based discovery**: Each `tenants/*/` directory becomes a tenant
2. **Helm baseline chart**: `helm/tenant-baseline` provides RBAC, quotas, network policies
3. **Per-tenant overrides**: `tenants/<name>/tenant.values.yaml` customizes resources
4. **Optional workloads**: `tenants/<name>/resources/` for tenant-specific apps
5. **Governance**: `tenants` AppProject limits namespace access (`team-*`)

To add a new tenant:
1. Create `tenants/<tenant-name>/tenant.values.yaml`
2. Set `tenantName: <tenant-name>`
3. Customize quotas, RBAC groups, network policies
4. ArgoCD auto-discovers and deploys

### Storage Configuration

Longhorn uses `/var/lib/longhorn` on the **Talos STATE partition** (configured in `infra/patches/user-volume.yaml`).

**Key points:**
- Safe for dev/test (no disk partitioning required)
- Shares space with system state
- Required system extensions in `cluster-template.yaml`:
  - `siderolabs/iscsi-tools`
  - `siderolabs/util-linux-tools`

**WARNING**: Never use machine config patches to mount additional disks on the system disk. This can break Talos. For dedicated storage disks, manually mount after cluster deployment.

### Secrets Management

This cluster integrates **Vault** with **External Secrets Operator**:

- Vault deployed in `argocd/apps/vault/vault/`
- ArgoCD uses `ExternalSecret` for credentials (`argocd/apps/argocd/argocd/argocd-external-secret.yaml`)
- Vault authenticates via Kubernetes token review (`vault/namespace/tokenreview-clusterrolebinding.yaml`)

## GitOps Workflow

1. **Modify files** in `argocd/apps/`, `tenants/`, or `helm/`
2. **Update repository URL** in `bootstrap-app-set.yaml` if using a fork
3. **Regenerate patches** if modifying ArgoCD bootstrap (see commands above)
4. **Commit and push** to the repository
5. ArgoCD **auto-syncs** applications (or manually sync via UI/CLI)

For infrastructure changes:
1. Modify `infra/cluster-template.yaml` or `infra/patches/`
2. Run `omnictl cluster template sync --file cluster-template.yaml`

## Important Notes

- **Repository URL**: Currently set to `https://github.com/matjahs/omni-cluster-1.git`. Update in:
  - `argocd/apps/argocd/argocd/bootstrap-app-set.yaml`
  - `argocd/apps/tenant-appset.yaml`
  - `argocd/apps/infra.yaml`

- **Machine Classes**: Cluster uses `k8s-rumc-01-nodes` and `k8s-rumc-01-workers`. These must exist in your Omni instance.

- **Omni Workload Proxy**: Enabled in `cluster-template.yaml` for accessing services without external ingress.

- **3-node cluster**: Control plane nodes act as workers (via `scheduling.yaml` patch).

- **Cilium handover**: ArgoCD adopts Cilium without downtime using `ServerSideApply` and `ignoreDifferences`.
