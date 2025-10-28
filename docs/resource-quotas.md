# Resource Quotas

Tenant resource limits to prevent resource exhaustion.

## Overview

Each tenant namespace has resource quotas that limit CPU, memory, and other resources.

## Default Quotas

Defined in `helm/tenant-baseline/values.yaml`:

```yaml
resourceQuota:
  enabled: true
  hard:
    requests.cpu: '2'
    requests.memory: 4Gi
    limits.cpu: '4'
    limits.memory: 8Gi
    pods: '25'
    services: '10'
```

## Current Tenant Quotas

### Team-A

```yaml
# tenants/team-a/tenant.values.yaml
resourceQuota:
  hard:
    requests.cpu: '4'
    limits.memory: 16Gi
```

### Team-B

Uses default quotas (see above).

## Checking Quota Usage

```bash
# View quota for team-a
kubectl get resourcequota -n team-a

# Detailed view
kubectl describe resourcequota -n team-a
```

**Example output:**
```
Name:            team-a-quota
Resource         Used   Hard
--------         ----   ----
limits.memory    4Gi    16Gi
pods             10     25
requests.cpu     2      4
services         3      10
```

## What Happens When Quota Is Exceeded?

### Pod Creation Fails

```bash
kubectl create deployment test -n team-a --image=nginx --replicas=100
# Error: exceeded quota: team-a-quota, requested: pods=100, used: pods=10, limited: pods=25
```

### Namespace Remains Functional

- Existing pods continue running
- Can delete pods to free up quota
- Other namespaces unaffected

## Customizing Quotas

Edit tenant configuration:

```yaml
# tenants/team-a/tenant.values.yaml
resourceQuota:
  hard:
    requests.cpu: '8'        # Increase CPU
    requests.memory: 16Gi    # Increase memory
    limits.cpu: '16'
    limits.memory: 32Gi
    pods: '50'               # More pods
    services: '20'
    persistentvolumeclaims: '10'  # Add PVC limit
```

Apply changes (ArgoCD will sync automatically).

## Limit Ranges

Default limits for pods without resource requests:

```yaml
# helm/tenant-baseline/values.yaml
limitRange:
  enabled: true
  default:          # Default limits
    cpu: 500m
    memory: 512Mi
  defaultRequest:   # Default requests
    cpu: 200m
    memory: 256Mi
```

This ensures all pods have resource limits, even if not specified.

## Monitoring Quota Usage

### Via kubectl

```bash
# All quotas in namespace
kubectl get resourcequota -n team-a -o yaml

# Watch quota changes
kubectl get resourcequota -n team-a --watch
```

### Via Metrics

If Prometheus is deployed:
```promql
kube_resourcequota{namespace="team-a"}
```

## Best Practices

1. **Set appropriate limits** based on workload requirements
2. **Monitor usage** regularly
3. **Adjust quotas** as tenant needs grow
4. **Use LimitRanges** to set defaults

## See Also

- **[Namespace Isolation](namespace-isolation.md)** - Complete isolation overview
- **[Network Policies](network-policies.md)** - Traffic control
