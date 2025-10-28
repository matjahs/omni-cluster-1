# ADR-003: Cilium Gateway API for Ingress

**Status:** Accepted

**Date:** 2025-10-19

**Deciders:** Platform Team

## Context

The cluster requires HTTP/HTTPS ingress to expose services like:
- ArgoCD UI
- Longhorn dashboard
- Prometheus/Grafana (monitoring stack)
- Tenant applications

Traditional Kubernetes ingress options:
1. **Ingress Controller** (nginx-ingress, Traefik)
   - Mature, widely adopted
   - Requires separate ingress controller deployment
   - Uses Ingress resources (v1 API)

2. **LoadBalancer Services**
   - Simple, direct exposure
   - Each service requires separate LoadBalancer IP
   - No path-based routing

3. **Gateway API** (Kubernetes SIG standard)
   - Newer, more expressive API
   - Role-oriented: Gateway (ops) vs HTTPRoute (devs)
   - Native support in modern CNIs (Cilium, Istio)

Cluster already uses **Cilium CNI**, which includes:
- Native Gateway API implementation
- L2/L7 traffic management
- No need for separate ingress controller

## Decision

We will use **Cilium Gateway API** for HTTP ingress.

### Configuration

#### 1. Enable Gateway API in Cilium

```yaml
# apps/kube-system/cilium/values.yaml
gatewayAPI:
  enabled: true
```

#### 2. Create Gateway Resource

```yaml
# apps/kube-system/cilium-config/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cilium-gateway
  namespace: kube-system
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: gateway-tls-cert
```

**Gateway responsibilities:**
- Listens on ports 80 (HTTP) and 443 (HTTPS)
- Terminates TLS using cert-manager certificates
- Managed by platform team (in `kube-system` namespace)

#### 3. Create HTTPRoute Resources

```yaml
# apps/longhorn-system/longhorn-config/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  parentRefs:
    - name: cilium-gateway
      namespace: kube-system
  hostnames:
    - longhorn.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: longhorn-frontend
          port: 80
```

**HTTPRoute responsibilities:**
- Defines routing rules (hostname, path)
- References backend services
- Owned by application teams (in their namespace)

#### 4. L2 Announcement for LoadBalancer IP

```yaml
# apps/kube-system/cilium-config/l2-policy.yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2-policy
spec:
  serviceSelector:
    matchLabels:
      io.cilium/gateway: cilium-gateway
  interfaces:
    - eth0
  externalIPs: true
  loadBalancerIPs: true
```

**L2 announcement:**
- Advertises Gateway LoadBalancer IP via ARP/NDP
- Enables direct access from local network
- No external MetalLB/cloud provider required

### Architecture

```
┌─────────────────────────────────────────────────┐
│  External Clients (HTTP/HTTPS)                  │
└─────────────────┬───────────────────────────────┘
                  │
                  ↓  (LoadBalancer IP via L2)
┌─────────────────────────────────────────────────┐
│  Cilium Gateway (kube-system)                   │
│  - TLS termination                              │
│  - Hostname-based routing                       │
└──────┬──────────────────────┬───────────────────┘
       │                      │
       ↓ HTTPRoute            ↓ HTTPRoute
┌──────────────────┐   ┌──────────────────┐
│ longhorn.ex.com  │   │ argocd.ex.com    │
│ → longhorn-      │   │ → argocd-server  │
│   frontend:80    │   │   :443           │
└──────────────────┘   └──────────────────┘
```

## Consequences

### Positive

- **Zero ingress controller**: Leverages existing Cilium CNI
- **Reduced resource usage**: No nginx/Traefik deployment
- **Role separation**: Ops manage Gateway, devs manage HTTPRoutes
- **Namespace isolation**: Routes live with applications
- **Future-proof**: Gateway API is Kubernetes SIG standard
- **Native TLS**: cert-manager integration via certificateRefs
- **L2 integration**: Direct LoadBalancer IP announcement

### Negative

- **Newer API**: Less mature than Ingress (but stable since K8s 1.31)
- **Learning curve**: Teams must learn Gateway API concepts
- **Limited tooling**: Fewer third-party tools compared to Ingress
- **Cilium dependency**: Tied to Cilium CNI (acceptable: already using it)

### Neutral

- **TLS termination**: Gateway terminates TLS, backends use HTTP
- **L2 announcement**: Works for on-prem/homelab, not needed in cloud environments

## Alternatives Considered

### Alternative 1: nginx-ingress Controller
**Rejected**: Requires additional deployment
- **Problem**: Extra resource usage (CPU/memory for nginx pods)
- **Problem**: Another component to manage and upgrade
- **Advantage**: Mature ecosystem, extensive annotations

### Alternative 2: Traefik Ingress Controller
**Rejected**: Similar to nginx-ingress
- **Problem**: Additional deployment and resource overhead
- **Advantage**: Native Gateway API support (but so does Cilium)

### Alternative 3: Multiple LoadBalancer Services
**Rejected**: No path-based routing
- **Problem**: Each service needs separate IP
- **Problem**: No centralized TLS management

### Alternative 4: Kubernetes Ingress API (v1)
**Rejected**: Gateway API is successor
- **Problem**: Less expressive than Gateway API
- **Problem**: Kubernetes deprecating Ingress in favor of Gateway API

## Related Decisions

- [ADR-001: Hybrid Bootstrap Pattern](001-hybrid-bootstrap-pattern.md) - Cilium deployed inline
- Gateway API is Kubernetes SIG standard (graduated to stable in K8s 1.31)

## References

- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Cilium Gateway API Documentation](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/)
- [apps/kube-system/cilium-config/gateway.yaml](../../apps/kube-system/cilium-config/gateway.yaml)
- Commit: [6caee74](../../.git)
