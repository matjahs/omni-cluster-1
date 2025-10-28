# ADR-004: Longhorn on Talos STATE Partition

**Status:** Accepted

**Date:** 2025-10-17

**Deciders:** Platform Team

## Context

Kubernetes workloads require persistent storage for:
- StatefulSets (databases, message queues)
- Application data (uploads, caches)
- Infrastructure storage (Vault Raft, Prometheus, Grafana)

Talos Linux has an immutable filesystem with specific partition layout:
- **BOOT**: EFI boot partition (read-only)
- **STATE**: Persistent state (/var, /etc/kubernetes) (read-write)
- **EPHEMERAL**: Temporary data (/tmp, container layers) (read-write, lost on reboot)

Longhorn requirements for storage:
- **iSCSI support**: Kernel modules for block device access
- **util-linux tools**: For filesystem management (mkfs, mount)
- **Writable directory**: Persistent storage location

Production storage options:
1. **Dedicated storage disks**: Separate physical/virtual disks for Longhorn
2. **STATE partition**: Use existing persistent partition
3. **Cloud provider storage**: EBS, Persistent Disks (not applicable for on-prem)

## Decision

We will configure Longhorn to use the **Talos STATE partition** at `/var/lib/longhorn`.

### Configuration

#### 1. Enable Required Talos System Extensions

```yaml
# bootstrap/talos/cluster-template.yaml
systemExtensions:
  - siderolabs/iscsi-tools      # iSCSI initiator support
  - siderolabs/util-linux-tools # Filesystem utilities
```

**Why these extensions:**
- `iscsi-tools`: Enables iSCSI block device attachment (Longhorn requirement)
- `util-linux-tools`: Provides `mkfs`, `mount`, and filesystem management tools

#### 2. Configure Machine Kubelet Mount (Previous Implementation)

The initial implementation used a machine config patch:

```yaml
# (Historical: infra/patches/user-volume.yaml)
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/mnt/longhorn-volume
        options:
          - bind
          - rshared
          - rw
```

**Note:** This patch has since been removed. The current implementation uses the default `/var/lib/longhorn` path which is on the STATE partition by default.

#### 3. Longhorn Configuration

```yaml
# apps/longhorn-system/longhorn/values.yaml
defaultSettings:
  defaultDataPath: /var/lib/longhorn
```

**Storage location:**
- `/var/lib/longhorn` is on the STATE partition
- STATE partition persists across reboots
- Shared across all worker nodes

### Why STATE Partition (Not Dedicated Disks)

**For dev/test environments:**
- ✅ **No disk partitioning**: No need to manually partition additional disks
- ✅ **Simplified setup**: Works immediately on cluster creation
- ✅ **Cost-effective**: No additional storage costs for homelab/test clusters
- ✅ **Sufficient for testing**: STATE partition typically has adequate space

**Trade-offs:**
- ⚠️ **Shared with system state**: Longhorn shares space with K8s etcd, logs
- ⚠️ **Not suitable for production**: Risk of filling system partition
- ⚠️ **Limited by STATE partition size**: Typically smaller than dedicated storage

### Production Migration Path

For production deployments, migrate to dedicated storage:

```yaml
# Add dedicated disk to machines
# /dev/sdb (dedicated Longhorn disk)

# Update Longhorn configuration
defaultSettings:
  defaultDataPath: /mnt/longhorn-storage

# Machine config patch
machine:
  disks:
    - device: /dev/sdb
      partitions:
        - mountpoint: /mnt/longhorn-storage
```

**Important:** Never use machine config patches to mount additional disks on the system disk. This can break Talos. For dedicated storage disks, manually mount after cluster deployment.

## Consequences

### Positive

- **Zero manual setup**: Cluster bootstrap includes storage
- **Simple for dev/test**: No disk partitioning required
- **Cost-effective**: No additional storage infrastructure
- **Fast iteration**: Rapid cluster rebuild/testing
- **Kubernetes-native**: Works with standard PVC/PV workflow

### Negative

- **Shared partition risk**: Longhorn can fill system partition
  - **Mitigation**: Set resource quotas, monitor disk usage
- **Not production-ready**: Should migrate to dedicated disks for prod
- **Limited storage capacity**: Constrained by STATE partition size
- **No storage isolation**: System and application data share partition

### Neutral

- **Talos extensions required**: Must include `iscsi-tools` and `util-linux-tools`
- **Performance**: STATE partition is typically on fast NVMe/SSD (acceptable)

## Alternatives Considered

### Alternative 1: Dedicated Storage Disks
**Deferred for production**: Use separate `/dev/sdb` for Longhorn
- **Advantage**: Storage isolation, larger capacity
- **Problem**: Requires manual disk provisioning and partitioning
- **Decision**: Start with STATE partition, migrate to dedicated disks for prod

### Alternative 2: Cloud Provider Storage (EBS, Persistent Disks)
**Not applicable**: On-prem/homelab cluster
- **Advantage**: Managed storage, high availability
- **Problem**: Requires cloud environment

### Alternative 3: NFS/CephFS External Storage
**Rejected**: Adds operational complexity
- **Advantage**: Centralized storage, snapshots
- **Problem**: Requires separate NFS/Ceph cluster
- **Problem**: Network overhead for block storage

### Alternative 4: Local Path Provisioner
**Rejected**: No replication, single-node storage
- **Advantage**: Extremely simple
- **Problem**: Data loss on node failure
- **Problem**: No pod migration (pods stuck on node with data)

## Related Decisions

- [ADR-002: Vault HA with Raft Storage and AWS KMS Auto-Unseal](002-vault-ha-raft-aws-kms.md) - Uses Longhorn PVs
- [ADR-006: ArgoCD Sync Waves for Bootstrap Ordering](006-argocd-sync-waves-for-bootstrap-ordering.md) - Longhorn in Wave 0

## References

- [Talos Linux Partitions](https://www.talos.dev/latest/learn-more/architecture/#partitions)
- [Longhorn Requirements](https://longhorn.io/docs/latest/deploy/install/#installation-requirements)
- [CLAUDE.md](../../CLAUDE.md) - Storage configuration section
- Commits: [a1824ea](../../.git), [c199e8a](../../.git)
