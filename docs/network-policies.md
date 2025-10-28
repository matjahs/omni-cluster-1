# Network Policies

Pod-to-pod traffic control between tenants.

## Overview

Network policies prevent pods in one tenant namespace from communicating with pods in another tenant namespace.

## Configuration

Configured in `helm/tenant-baseline/values.yaml`:

```yaml
networkPolicy:
  enabled: true
  allowVault: true         # Access to Vault
  allowMonitoring: true    # Prometheus scraping
  allowIngress: true       # Cilium Gateway/Ingress
  allowExternal: true      # External HTTPS
  otherTenantNamespaces: []  # Other tenants to block
```

## How It Works

### Default Rules

**Allowed:**
- ✅ Pods can access Vault (for secrets)
- ✅ Prometheus can scrape pod metrics
- ✅ Ingress/Gateway can route traffic to pods
- ✅ Pods can make outbound HTTPS calls

**Blocked:**
- ❌ Pods in team-a cannot reach pods in team-b
- ❌ Pods in team-b cannot reach pods in team-a

### Cross-Tenant Blocking

To explicitly block traffic to team-b from team-a:

```yaml
# tenants/team-a/tenant.values.yaml
networkPolicy:
  otherTenantNamespaces:
    - team-b
    - team-c
```

## Testing Network Isolation

### Create Test Pods

```bash
# In team-a
kubectl run test-a -n team-a --image=nginx

# In team-b
kubectl run test-b -n team-b --image=nginx
```

### Test Cross-Tenant Connection

```bash
# Try to connect from team-a to team-b
kubectl exec -n team-a test-a -- curl http://test-b.team-b.svc.cluster.local --max-time 5
# Result: Timeout (blocked by network policy)
```

### Test Internal Connection

```bash
# Within same namespace should work
kubectl exec -n team-a test-a -- curl http://localhost
# Result: Success
```

## Customization

### Allow External Database Access

```yaml
# tenants/team-a/tenant.values.yaml
networkPolicy:
  allowExternalDB: true
  allowedDatabases:
    - postgres
    - mysql
```

### Custom Cilium Policies

```yaml
networkPolicy:
  customCiliumPolicies:
    - name: allow-specific-service
      spec:
        endpointSelector:
          matchLabels:
            app: myapp
        egress:
          - toEndpoints:
            - matchLabels:
                app: external-api
```

## See Also

- **[Namespace Isolation](namespace-isolation.md)** - Complete isolation overview
- **[Resource Quotas](resource-quotas.md)** - Tenant resource limits
