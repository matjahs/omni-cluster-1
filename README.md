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
omnictl cluster template sync --file cluster-template.yaml
```

Omni will then being to allocate your machines, install Talos, and configure and bootstrap the cluster.

This setup makes use of the [Omni Workload Proxy](https://omni.siderolabs.com/how-to-guides/expose-an-http-service-from-a-cluster) feature,
which allows access to the HTTP front end services *without* the need of a separate external Ingress Controller or LoadBalancer.
Additionally, it leverages Omni's built-in authentication to protect the services, even those services that don't support authentication themselves.

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
