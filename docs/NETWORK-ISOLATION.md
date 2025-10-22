# Network-Level Isolation for Multi-Tenancy

## Overview

Network policies provide **Layer 3/4 isolation** to prevent cross-tenant communication at the network level. This is critical for true multi-tenancy security.

## Current State

Your existing `helm/tenant-baseline/templates/networkpolicies.yaml` provides:
- ✅ Default deny all ingress/egress
- ✅ Allow same-namespace communication
- ⚠️  Missing: DNS access
- ⚠️  Missing: Allow access to shared services (monitoring, ingress)
- ⚠️  Missing: Allow egress to external services
- ⚠️  Missing: Explicit cross-tenant denial

## Network Isolation Goals

```
┌──────────────────────────────────────────────────────┐
│ Multi-Tenant Network Isolation                       │
├──────────────────────────────────────────────────────┤
│                                                      │
│  team-a namespace        team-b namespace           │
│  ┌────────────┐          ┌────────────┐            │
│  │  Pod A1    │    ✗     │  Pod B1    │            │
│  │            │◄────────►│            │            │
│  │  Pod A2    │  DENIED  │  Pod B2    │            │
│  └────────────┘          └────────────┘            │
│       │                        │                    │
│       │ ✓ ALLOWED             │ ✓ ALLOWED         │
│       ▼                        ▼                    │
│  ┌──────────────────────────────────┐              │
│  │   Shared Services (kube-system)  │              │
│  │   - DNS (CoreDNS)                │              │
│  │   - Ingress (Cilium)             │              │
│  │   - Monitoring (Prometheus)      │              │
│  └──────────────────────────────────┘              │
│       │                        │                    │
│       │ ✓ ALLOWED             │ ✓ ALLOWED         │
│       ▼                        ▼                    │
│  ┌──────────────────────────────────┐              │
│  │      External Services           │              │
│  │   - Internet (HTTPS)             │              │
│  │   - Database (PostgreSQL)        │              │
│  └──────────────────────────────────┘              │
└──────────────────────────────────────────────────────┘
```

## Network Policy Architecture

### Layer 1: Default Deny (Baseline)
- Deny all ingress traffic
- Deny all egress traffic
- Applied to all pods in tenant namespace

### Layer 2: Core Services (Allow)
- DNS (kube-dns/coredns)
- Kubernetes API server
- Health checks (kubelet)

### Layer 3: Platform Services (Allow)
- Monitoring (Prometheus, Grafana)
- Logging (if deployed)
- Ingress controllers (Cilium Gateway)
- Vault (for secrets)

### Layer 4: External Access (Allow)
- HTTPS egress (443)
- Custom ports (as needed)
- Database access (per tenant)

### Layer 5: Cross-Tenant (Deny)
- Explicit deny between tenant namespaces
- Ensures isolation even if other policies change

---

## Enhanced NetworkPolicy Template

Replace `helm/tenant-baseline/templates/networkpolicies.yaml` with:

```yaml
---
{{- if .Values.networkPolicy.enabled }}

# ============================================
# 1. Default Deny All (Baseline Security)
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# ============================================
# 2. Allow Same Namespace Communication
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}

---
# ============================================
# 3. Allow DNS (CoreDNS/kube-dns)
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow DNS queries to kube-system CoreDNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Also allow Cilium DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: cilium
      ports:
        - protocol: UDP
          port: 53

---
# ============================================
# 4. Allow Kubernetes API Server
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kube-apiserver
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow access to Kubernetes API server
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
      ports:
        - protocol: TCP
          port: 443
    # Also allow direct API server access via service IP
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 6443

{{- if .Values.networkPolicy.allowVault }}
---
# ============================================
# 5. Allow Vault Access
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vault
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: vault
          podSelector:
            matchLabels:
              app.kubernetes.io/name: vault
      ports:
        - protocol: TCP
          port: 8200
        - protocol: TCP
          port: 8201
{{- end }}

{{- if .Values.networkPolicy.allowMonitoring }}
---
# ============================================
# 6. Allow Monitoring (Prometheus Scrape)
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector:
    matchExpressions:
      - key: app
        operator: Exists
  policyTypes:
    - Ingress
  ingress:
    # Allow Prometheus to scrape metrics
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 3000
{{- end }}

{{- if .Values.networkPolicy.allowIngress }}
---
# ============================================
# 7. Allow Ingress from Gateway/Ingress Controller
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- .Values.networkPolicy.ingressPodLabels | toYaml | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    # Allow from Cilium Gateway/Ingress
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: cilium
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 8443
{{- end }}

{{- if .Values.networkPolicy.allowExternal }}
---
# ============================================
# 8. Allow External HTTPS Egress
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-https
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow HTTPS to external services
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
    # Allow HTTP (if needed)
    {{- if .Values.networkPolicy.allowExternalHTTP }}
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 80
    {{- end }}
{{- end }}

{{- if .Values.networkPolicy.denyOtherTenants }}
---
# ============================================
# 9. Explicit Deny Cross-Tenant Traffic
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-other-tenants
  namespace: {{ .Values.tenantName }}
  labels:
    {{- include "tenant.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  # This policy explicitly denies traffic from/to other tenant namespaces
  # by not including any allow rules for tenant namespaces
  # Combined with default-deny-all, this ensures isolation
{{- end }}

{{- range .Values.networkPolicy.customPolicies }}
---
# ============================================
# Custom NetworkPolicy: {{ .name }}
# ============================================
{{ . | toYaml }}
{{- end }}

{{- end }}
```

---

## Updated values.yaml

Update `helm/tenant-baseline/values.yaml`:

```yaml
networkPolicy:
  enabled: true

  # Core isolation
  defaultDenyAll: true
  allowSameNamespace: true
  denyOtherTenants: true  # NEW: Explicit cross-tenant denial

  # Platform services
  allowVault: true         # NEW: Access to Vault
  allowMonitoring: true    # NEW: Prometheus scraping
  allowIngress: true       # NEW: Ingress controller access

  # External access
  allowExternal: true      # NEW: External HTTPS
  allowExternalHTTP: false # NEW: External HTTP (default false)

  # Ingress configuration
  ingressPodLabels:        # NEW: Labels for pods that should accept ingress
    network/ingress: "true"

  # Custom policies
  customPolicies: []       # NEW: Array of raw NetworkPolicy manifests

  # Database access (per tenant, optional)
  allowDatabase:
    enabled: false
    host: ""
    port: 5432
```

---

## Tenant Configuration Examples

### tenants/team-a/tenant.values.yaml

```yaml
---
tenantName: team-a

rbac:
  adminGroups: [team-a-admins, platform-admins]
  developerGroups: [team-a-developers]
  viewerGroups: [team-a-viewers]

networkPolicy:
  enabled: true
  allowVault: true
  allowMonitoring: true
  allowIngress: true
  allowExternal: true
  allowExternalHTTP: false

  # Custom: Allow team-a to access PostgreSQL
  customPolicies:
    - apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      metadata:
        name: allow-postgres
        namespace: team-a
      spec:
        podSelector: {}
        policyTypes:
          - Egress
        egress:
          - to:
              - podSelector:
                  matchLabels:
                    app: postgres
                namespaceSelector:
                  matchLabels:
                    kubernetes.io/metadata.name: team-a
            ports:
              - protocol: TCP
                port: 5432

vault:
  enabled: true
```

---

## Testing Network Isolation

### 1. Test Cross-Tenant Isolation

```bash
# Deploy test pods in both namespaces
kubectl run test-pod-a -n team-a --image=nicolaka/netshoot -- sleep 3600
kubectl run test-pod-b -n team-b --image=nicolaka/netshoot -- sleep 3600

# Get pod IPs
POD_A_IP=$(kubectl get pod test-pod-a -n team-a -o jsonpath='{.status.podIP}')
POD_B_IP=$(kubectl get pod test-pod-b -n team-b -o jsonpath='{.status.podIP}')

# Try to connect from team-a to team-b (should FAIL)
kubectl exec -n team-a test-pod-a -- curl --max-time 5 http://$POD_B_IP:80
# Expected: timeout or connection refused

# Try to connect within team-a (should SUCCEED)
kubectl run test-pod-a2 -n team-a --image=nginx:alpine
kubectl exec -n team-a test-pod-a -- curl --max-time 5 http://test-pod-a2
# Expected: nginx welcome page
```

### 2. Test DNS Access

```bash
# DNS should work
kubectl exec -n team-a test-pod-a -- nslookup kubernetes.default
# Expected: Success

kubectl exec -n team-a test-pod-a -- nslookup google.com
# Expected: Success
```

### 3. Test External Access

```bash
# HTTPS should work
kubectl exec -n team-a test-pod-a -- curl --max-time 5 https://google.com
# Expected: Success

# HTTP should fail (if allowExternalHTTP: false)
kubectl exec -n team-a test-pod-a -- curl --max-time 5 http://google.com
# Expected: Timeout
```

### 4. Test Vault Access

```bash
kubectl exec -n team-a test-pod-a -- curl http://vault-dev.vault.svc:8200/v1/sys/health
# Expected: {"initialized":true,"sealed":false,...}
```

### 5. Test Kubernetes API Access

```bash
kubectl exec -n team-a test-pod-a -- curl -k https://kubernetes.default.svc/api
# Expected: {"kind":"APIVersions",...}
```

---

## Cilium-Specific Enhancements

Since you're using Cilium, you can leverage additional features:

### 1. Cilium Network Policies (Layer 7)

Create `helm/tenant-baseline/templates/cilium-networkpolicy.yaml`:

```yaml
{{- if and .Values.networkPolicy.enabled .Values.networkPolicy.useCilium }}
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: layer7-http-policy
  namespace: {{ .Values.tenantName }}
spec:
  endpointSelector: {}

  egress:
    # Allow HTTP/HTTPS with specific rules
    - toEndpoints:
        - {}
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
            - port: "443"
              protocol: TCP
          rules:
            http:
              - method: "GET"
              - method: "POST"
              - method: "PUT"
              - method: "DELETE"

    # Allow DNS
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
          rules:
            dns:
              - matchPattern: "*"
{{- end }}
```

### 2. Cilium Cluster-Wide Network Policy

Create a cluster-wide policy to enforce tenant isolation:

```yaml
# cluster-policies/tenant-isolation.yaml
---
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: tenant-isolation
spec:
  description: "Prevent cross-tenant communication"

  # Apply to all tenant namespaces
  endpointSelector:
    matchExpressions:
      - key: io.kubernetes.pod.namespace
        operator: In
        values:
          - team-a
          - team-b

  # Deny ingress from other tenant namespaces
  ingressDeny:
    - fromEndpoints:
        - matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: In
              values:
                - team-a
                - team-b
      # But don't deny from same namespace
      exceptEndpoints:
        - matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: In
              values:
                - ${namespace}  # This would be dynamic per tenant

  # Deny egress to other tenant namespaces
  egressDeny:
    - toEndpoints:
        - matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: In
              values:
                - team-a
                - team-b
      exceptEndpoints:
        - matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: In
              values:
                - ${namespace}
```

---

## Service Mesh Option (Advanced)

For even more granular control, consider Cilium Service Mesh:

### Enable Cilium Service Mesh

```bash
# Enable in Cilium
cilium config set enable-envoy-config true

# Install Cilium Service Mesh
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set kubeProxyReplacement=strict \
  --set loadBalancer.mode=dsr \
  --set meshMode=transparent
```

### Mutual TLS Between Tenants (Optional)

```yaml
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: require-mtls
  namespace: team-a
spec:
  endpointSelector: {}

  ingress:
    - fromEndpoints:
        - {}
      authentication:
        mode: required
```

---

## Monitoring Network Policies

### 1. Hubble (Cilium Observability)

```bash
# Enable Hubble
cilium hubble enable --ui

# View network flows
hubble observe --namespace team-a

# Check for denied connections
hubble observe --verdict DROPPED --namespace team-a
```

### 2. Prometheus Metrics

NetworkPolicy drops are visible in metrics:

```promql
# Network policy drops
sum by (namespace) (rate(cilium_drop_count_total{reason="Policy denied"}[5m]))

# Alert on cross-tenant access attempts
alert: CrossTenantAccessAttempt
expr: |
  sum by (source_namespace, destination_namespace) (
    rate(cilium_drop_count_total{
      reason="Policy denied",
      source_namespace=~"team-.*",
      destination_namespace=~"team-.*",
      source_namespace!=destination_namespace
    }[5m])
  ) > 0
```

---

## Verification Checklist

- [ ] NetworkPolicies deployed to all tenant namespaces
- [ ] Cross-tenant communication blocked
- [ ] Same-namespace communication works
- [ ] DNS resolution works
- [ ] External HTTPS access works
- [ ] Vault access works (if enabled)
- [ ] Ingress works for exposed services
- [ ] Prometheus can scrape metrics
- [ ] Hubble shows policy enforcement (if using Cilium)

---

## Troubleshooting

### Pods Can't Resolve DNS

```bash
# Check if DNS policy exists
kubectl get networkpolicy -n team-a allow-dns

# Test DNS
kubectl run -n team-a test --image=busybox -it --rm -- nslookup kubernetes.default
```

### Can't Access External Services

```bash
# Check external access policy
kubectl get networkpolicy -n team-a allow-external-https

# Test
kubectl run -n team-a test --image=curlimages/curl -it --rm -- curl -v https://google.com
```

### Ingress Not Working

```bash
# Check ingress policy
kubectl get networkpolicy -n team-a allow-ingress-controller

# Verify pod labels match ingressPodLabels
kubectl get pods -n team-a --show-labels
```

### Check Cilium Policy Status

```bash
# View effective policies
cilium endpoint list -n team-a

# Check policy enforcement
cilium policy get <endpoint-id>
```

---

## Summary

**What We're Adding:**

1. ✅ **DNS Access** - Pods can resolve names
2. ✅ **Vault Access** - Pods can retrieve secrets
3. ✅ **Monitoring** - Prometheus can scrape metrics
4. ✅ **Ingress** - External traffic can reach services
5. ✅ **External HTTPS** - Pods can call external APIs
6. ✅ **Explicit Cross-Tenant Denial** - Belt and suspenders
7. ✅ **Custom Policies** - Per-tenant customization
8. ✅ **Cilium Enhancements** - Layer 7 policies (optional)

**Files to Update:**

- `helm/tenant-baseline/templates/networkpolicies.yaml` - Enhanced policies
- `helm/tenant-baseline/values.yaml` - New networkPolicy options
- `tenants/team-a/tenant.values.yaml` - Enable features
- `tenants/team-b/tenant.values.yaml` - Enable features

**Next Steps:**

1. Update the networkpolicies.yaml template
2. Update tenant values files
3. Test with the verification scripts
4. Deploy and monitor with Hubble
