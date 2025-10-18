# Structure

```text
.
├─ .gitignore
├─ BOOTSTRAP.md  # Instructions to bootstrap ArgoCD and initial infrastructure
├─ README.md     # Readme file
├─ STRUCTURE.md  # This file
├─ apps/         # All Kubernetes applications (infrastructure and workloads)
│  └─ ...
├─ argocd/       # ArgoCD project and application definitions
│  └─ ...
├─ bootstrap/    # Talos cluster bootstrap configuration
│  └─ ...
├─ helm/         # Helm chart for tenant baseline
│  └─ ...
└─ tenants/      # Tenant directories \(one namespace per team\)
   └─ ...
```

## ArgoCD

The ArgoCD folder contains the project and application definitions to bootstrap the cluster. The `projects/` folder
contains the ArgoCD Project definition for the tenants, while the `apps/` folder contains the ApplicationSet to generate
one Application per tenant based on the Helm chart and optional Kustomize manifests. It also contains an Application for
shared infrastructure components.

```text
├─ argocd/
│  ├─ projects/
│  │  └─ tenants-project.yaml
│  └─ apps/
│     ├─ tenants-appset.yaml            # Generates one Application per tenant \(Helm + optional Kustomize app\)
│     └─ infra.yaml                     # Defines shared cluster add-ons such as cert-manager and ingress
```

## Bootstrap

The bootstrap folder contains Talos cluster configuration files needed to bootstrap the Kubernetes cluster using Omni. This includes
the `cluster-template.yaml` file defining the cluster structure and machine classes.

```text
├─ bootstrap/
│  └─ talos/
│     ├─ cluster-template.yaml   # Omni cluster template defining control plane and worker nodes
│     └─ patches/
│        ├─ ...
│        └─ 00-cni.yaml          # Example patch to modify worker machine

```

## Apps

The apps folder contains all Kubernetes applications managed by ArgoCD via GitOps. This includes infrastructure
components (ArgoCD, Cilium, Vault, Longhorn, monitoring) deployed cluster-wide. Each application follows the
`namespace/application-name` structure and contains Helm values files or Kustomize configurations.

```text
├─ apps/
│  ├─ argocd/argocd/                    # ArgoCD self-management
│  ├─ cert-manager/
│  │  └─ values.yaml                    # Minimal tuned values for cert-manager installation
│  ├─ kube-system/cilium/               # Cilium CNI (managed after bootstrap handover)
│  ├─ longhorn-system/longhorn/         # Persistent storage
│  ├─ monitoring/kube-prometheus-stack/ # Prometheus & Grafana
│  └─ vault/vault/                      # Secrets management
```

## Helm Chart - Tenant Baseline

The Helm chart defines the baseline resources created for each tenant/namespace. This includes the namespace itself,
RBAC roles, resource quotas, network policies,

```text
├─ helm/
│  └─ tenant-baseline/                  # Helm chart defining namespace/RBAC/quotas/netpols \(+ extras\)
│     ├─ Chart.yaml
│     ├─ values.yaml
│     └─ templates/
│        ├─ namespace.yaml
│        ├─ rbac.yaml
│        ├─ resourcequota.yaml
│        ├─ limitrange.yaml
│        ├─ networkpolicies.yaml
│        ├─ podsecuritylabels.yaml
│        ├─ serviceaccount.yaml
│        ├─ extras-configmap.yaml
│        ├─ _helpers.tpl
│        └─ values.schema.json          # Schema validation for values files
```

## Tenants

The tenants folder contains one directory per tenant/team/namespace. Each tenant directory contains a
`tenant.values.yaml` file to configure the baseline Helm chart, and an optional `app/` directory containing Kustomize
manifests for tenant-specific applications.

```text
...
│                                      # Tenant directories \(one namespace per team\)
├─ tenants/
│  ├─ team-a/
│  │  ├─ tenant.values.yaml             # Helm baseline values and feature toggles
│  │  └─ app/
│  │     ├─ kustomization.yaml
│  │     ├─ deployment.yaml
│  │     └─ service.yaml
│  └─ team-b/
│     ├─ tenant.values.yaml
│     └─ app/
│        ├─ kustomization.yaml
│        ├─ deployment.yaml
│        └─ service.yaml
```
