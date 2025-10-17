# Siderolabs Omni Example

This example shows how to manage a Talos Kubernetes cluster with Sidero Labs' Omni.
It deploys a Talos Kubernetes cluster using Omni, with the following tooling:

* Cilium for CNI & Hubble UI for observability
* ArgoCD for application management
* Longhorn for persistent volume management
* Prometheus & Grafana for monitoring

## Prereqs

An [Omni account](https://signup.siderolabs.io/), and some machines registered to it.
How the machines are started and joined to the Omni instance are not covered in this README, but [documentation is available](https://omni.siderolabs.com/tutorials/getting_started/).
With the default configuration, a minimum of 3 machines that can serve as both control plane and worker nodes. Longhorn will use the root filesystem for storage by default, though dedicated block devices can be configured if desired.

This example uses [Machine Classes](https://omni.siderolabs.com/how-to-guides/create-a-machine-class) called `omni-contrib-controlplane` and `omni-contrib-workers`.
How they are defined is entirely dependent on the infrastructure available, they would need to be configured on the Omni instance.

Lastly, `omnictl` the Omni CLI tool would also be needed.
See the [How-to](https://omni.siderolabs.com/how-to-guides/install-and-configure-omnictl) on how to obtain and configure it.

## Usage

Once the required machines are registered to Omni and machine classes have been configured, simply run

```bash
cd infra
omnictl cluster template sync --file cluster-template.yaml
```

Omni will then being to allocate your machines, install Talos, and configure and bootstrap the cluster.

### Deployment Order

This cluster uses a **hybrid bootstrap pattern** for critical infrastructure:

#### Bootstrap Phase (Inline Manifests)
The following components are deployed immediately via Omni cluster patches:
- **Cilium CNI** - Required for any pod networking
- **ArgoCD** - Bootstraps itself and manages other applications

These are deployed as inline manifests to ensure they're available before any other workloads.

#### ArgoCD Management Phase (Sync Waves)
After bootstrap, ArgoCD takes over management and deploys applications in waves:

**Wave -1** (Infrastructure Handover):
- **Cilium** - ArgoCD takes over management from inline manifest
  - Uses `ServerSideApply` to adopt existing resources
  - `ignoreDifferences` for dynamically generated certs and runtime fields

**Wave 0** (Storage):
- **Longhorn** - Persistent storage must be ready first
- **Namespace creation**

**Wave 1** (Applications):
- **Prometheus & Grafana** - Requires Longhorn for persistent storage
- **Other applications**

#### How Cilium Handover Works

1. **Cluster Creation**: Cilium deployed via inline manifest (immediate CNI)
2. **ArgoCD Starts**: Discovers `apps/kube-system/cilium` in git
3. **Resource Adoption**: ArgoCD adopts existing Cilium resources using Server-Side Apply
4. **Ongoing Management**: Future updates via git are applied by ArgoCD

This ensures zero downtime - Cilium is never removed, just managed by ArgoCD after bootstrap.

### Omni Features

This setup makes use of the [Omni Workload Proxy](https://omni.siderolabs.com/how-to-guides/expose-an-http-service-from-a-cluster) feature,
which allows access to the HTTP front end services *without* the need of a separate external Ingress Controller or LoadBalancer.
Additionally, it leverages Omni's built-in authentication to protect the services, even those services that don't support authentication themselves.

## Storage Configuration

This cluster uses Longhorn for persistent storage.

### ⚠️ IMPORTANT: Default Configuration (System Disk)

The current configuration uses `/var/lib/longhorn` on the **STATE partition** of the system disk. This is configured via kubelet extraMounts in [user-volume.yaml](infra/patches/user-volume.yaml).

**This configuration:**
- ✅ Works immediately without additional setup
- ✅ Safe - does NOT modify disk partitions
- ✅ Suitable for development and testing
- ⚠️ Shares space with system state (logs, kubelet data, etc.)

### Using Additional Disks (Advanced)

**WARNING**: Modifying Talos disk configurations can break your cluster if done incorrectly. The system disk should NEVER be reconfigured via machine patches.

If you want to use dedicated disks for Longhorn:
1. **Do NOT** use machine config patches to mount disks
2. **Instead**, manually mount disks after cluster deployment:
   ```bash
   # Example: Mount additional disk
   mount /dev/sdb1 /var/mnt/longhorn-disk1
   ```
3. Then configure Longhorn via the UI to use those paths

### Checking Available Space

To check available space for Longhorn:
```bash
# From a Talos node console (via Omni)
df -h | grep STATE
```

The STATE partition is typically on `/dev/sda3` and has sufficient space for most workloads.

### Required System Extensions
The cluster template includes the necessary Talos system extensions for Longhorn:
- `siderolabs/iscsi-tools` - iSCSI support for Longhorn
- `siderolabs/util-linux-tools` - Disk utilities

## Applications

Applications are managed by ArgoCD, and are defined in the `apps` directory.
The first subdirectory defines the namespace and the second being the application name.
Applications can be made of Helm charts, Kustomize definitions, or just Kubernetes manifest files in YAML format.

## Extending

ArgoCD is configured to use this repository at `https://github.com/matjahs/omni-cluster-1.git` to manage applications.

To modify applications:
1. Make changes to the Helm charts or manifests in the `apps` directory
2. Update the ArgoCD repository URL in [bootstrap-app-set.yaml](apps/argocd/argocd/bootstrap-app-set.yaml) if you fork this repository
3. Regenerate the ArgoCD bootstrap cluster manifest patch [argocd.yaml](infra/patches/argocd.yaml) (instructions can be found at the top of that file)
4. Commit and push changes to your repository
5. Sync the cluster template with Omni as described above

## About This Repository

This repository is a customized fork of the [Siderolabs Omni Examples](https://github.com/siderolabs/contrib) with the following modifications:
* Replaced Rook-Ceph with Longhorn for persistent storage
* Configured for 3-node clusters with control plane nodes acting as workers
* Enabled Cilium Gateway API support
* Optimized replica counts and resource settings for smaller clusters
