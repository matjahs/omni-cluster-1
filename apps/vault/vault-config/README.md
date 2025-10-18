# Vault Configuration Guide

This directory contains configuration files and scripts to set up HashiCorp Vault with External Secrets Operator integration for the Kubernetes cluster.

## Overview

The configuration includes:
- **Kubernetes Authentication**: Allows pods to authenticate with Vault using their ServiceAccount
- **Vault Policies**: RBAC-style policies for ArgoCD, applications, and tenants
- **External Secrets Operator**: Integration to sync secrets from Vault to Kubernetes
- **Example Secrets**: Templates for common use cases

## Architecture

```
┌─────────────────┐
│   Application   │
│      Pod        │
└────────┬────────┘
         │ Reads K8s Secret
         ▼
┌─────────────────┐
│  Kubernetes     │
│    Secret       │
└────────┬────────┘
         │ Synced by ESO
         ▼
┌─────────────────┐      ┌──────────────────┐
│  ExternalSecret │─────▶│  SecretStore     │
│   Resource      │      │   (Vault config) │
└─────────────────┘      └────────┬─────────┘
                                  │
                                  │ K8s Auth
                                  ▼
                         ┌──────────────────┐
                         │      Vault       │
                         │   secret/data/*  │
                         └──────────────────┘
```

## Quick Start

### Prerequisites

1. Vault is running and initialized (check `vault.env` for root token)
2. External Secrets Operator is deployed
3. `kubectl` access to the cluster
4. Vault CLI installed locally OR port-forward to Vault pod

### Setup Steps

#### 1. Access Vault

**Option A: Via Omni Workload Proxy**
```bash
# Find the Vault URL in Omni console
export VAULT_ADDR="<omni-vault-url>"
export VAULT_TOKEN="<root-token-from-vault.env>"
```

**Option B: Via Port Forward**
```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="<root-token-from-vault.env>"
```

#### 2. Enable Kubernetes Auth

```bash
cd apps/vault/vault-config
./01-enable-k8s-auth.sh
```

This enables the Kubernetes auth backend and configures it to communicate with the cluster.

#### 3. Create Vault Policies

```bash
./02-create-policies.sh
```

Creates the following policies:
- **argocd**: Read access to `secret/data/argocd/*` and `secret/data/apps/*`
- **apps**: Read access to `secret/data/apps/<namespace>/*`
- **tenants**: Full access to `secret/data/tenants/<namespace>/*`
- **external-secrets**: Read access to all secrets (for ESO)

#### 4. Create Kubernetes Auth Roles

```bash
./03-create-roles.sh
```

Creates roles that bind ServiceAccounts to policies:
- **argocd**: For ArgoCD service accounts
- **external-secrets**: For ESO service account
- **app**: For default service accounts in any namespace
- **tenant**: For default service accounts in `team-*` namespaces

#### 5. Populate Example Secrets

```bash
./04-populate-secrets.sh
```

Creates example secrets for testing:
- `secret/argocd/admin` - ArgoCD admin password
- `secret/apps/my-app/database` - Database credentials
- `secret/tenants/team-a/config` - Tenant configuration

#### 6. Deploy SecretStores

```bash
# Deploy ClusterSecretStore (cluster-wide access)
kubectl apply -f cluster-secret-store.yaml

# Deploy SecretStore for ArgoCD namespace
kubectl apply -f secret-store-argocd.yaml
```

#### 7. Test with ExternalSecret

```bash
# Deploy example ExternalSecret for ArgoCD
kubectl apply -f external-secret-example-argocd.yaml

# Check if secret was created
kubectl get secret -n argocd argocd-secret
kubectl get externalsecret -n argocd argocd-secret

# View the synced secret
kubectl get secret -n argocd argocd-secret -o jsonpath='{.data.admin\.password}' | base64 -d
```

## Vault Secret Structure

```
secret/
├── argocd/
│   ├── admin           # Admin credentials
│   ├── server          # Server secrets
│   └── repo            # Repository credentials
├── apps/
│   └── <namespace>/
│       └── <app-name>/ # Application-specific secrets
└── tenants/
    └── <team-name>/    # Tenant-specific secrets
```

## Common Operations

### Adding a New Application Secret

1. **Create secret in Vault:**
   ```bash
   vault kv put secret/apps/my-namespace/my-app \
     api_key="secret-value" \
     database_url="postgresql://..."
   ```

2. **Create ExternalSecret resource:**
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: my-app-secrets
     namespace: my-namespace
   spec:
     refreshInterval: 15m
     secretStoreRef:
       name: vault-backend
       kind: ClusterSecretStore
     target:
       name: my-app-secrets
     dataFrom:
       - extract:
           key: apps/my-namespace/my-app
   ```

3. **Apply the ExternalSecret:**
   ```bash
   kubectl apply -f my-app-external-secret.yaml
   ```

### Adding Tenant Secrets

1. **Create tenant secret in Vault:**
   ```bash
   vault kv put secret/tenants/team-b/config \
     api_key="team-b-key" \
     environment="staging"
   ```

2. **Tenants can manage their own secrets** (if given Vault access):
   ```bash
   # Tenant authenticates with their ServiceAccount token
   vault write auth/kubernetes/login \
     role=tenant \
     jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

   # Tenant creates/updates secrets
   vault kv put secret/tenants/team-b/app-config \
     key=value
   ```

### Viewing Secrets

```bash
# List secrets
vault kv list secret/argocd
vault kv list secret/apps
vault kv list secret/tenants

# Get secret
vault kv get secret/argocd/admin
vault kv get -format=json secret/apps/my-app/database | jq '.data.data'

# Get specific field
vault kv get -field=password secret/argocd/admin
```

### Rotating Secrets

```bash
# Update secret in Vault
vault kv put secret/argocd/admin password="new-password"

# ESO will automatically sync the new value within the refreshInterval
# Check ExternalSecret status
kubectl get externalsecret -n argocd argocd-secret -o yaml

# Force immediate sync (delete the secret, ESO will recreate)
kubectl delete secret -n argocd argocd-secret
```

## Policies Explained

### ArgoCD Policy
```hcl
path "secret/data/argocd/*" {
  capabilities = ["read", "list"]
}
path "secret/data/apps/*" {
  capabilities = ["read", "list"]
}
```
- Allows ArgoCD to read its own secrets and all app secrets
- Used by ArgoCD to deploy applications with secrets

### Apps Policy
```hcl
path "secret/data/apps/{{identity.entity.aliases.AUTH_MOUNT_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}
```
- Uses Vault templating to restrict access to namespace-specific secrets
- Apps can only read secrets in their own namespace path

### Tenants Policy
```hcl
path "secret/data/tenants/{{identity.entity.aliases.AUTH_MOUNT_ACCESSOR.metadata.service_account_namespace}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```
- Tenants have full CRUD access to their namespace path
- Enables self-service secret management for tenants

## Troubleshooting

### ExternalSecret not syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret -n <namespace> <name>

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Verify SecretStore configuration
kubectl get secretstore -n <namespace> vault-backend -o yaml

# Test Vault authentication manually
kubectl run vault-test --rm -it --image=vault:latest -- sh
vault login -method=kubernetes role=external-secrets
vault kv get secret/argocd/admin
```

### Permission denied errors

```bash
# Check Vault policy
vault policy read argocd

# Check role configuration
vault read auth/kubernetes/role/argocd

# Verify ServiceAccount has correct permissions
kubectl get clusterrolebinding vault-tokenreview-binding -o yaml
```

### Vault sealed

```bash
# Check vault status
kubectl exec -n vault vault-0 -- vault status

# Unseal vault (requires 3 of 5 unseal keys from vault.env)
kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <key-3>
```

## Security Best Practices

1. **Rotate Root Token**: After initial setup, create limited-privilege tokens
   ```bash
   vault token create -policy=admin
   # Revoke root token
   vault token revoke <root-token>
   ```

2. **Secure Unseal Keys**: Store unseal keys in a secure location (not in Git!)
   - Consider using auto-unseal with cloud KMS
   - Split keys among multiple administrators

3. **Audit Logging**: Enable audit logging
   ```bash
   vault audit enable file file_path=/vault/audit/audit.log
   ```

4. **Least Privilege**: Create specific policies for each use case
   ```bash
   # Don't use the root token for applications
   # Create service-specific tokens/roles
   ```

5. **Secret Rotation**: Regularly rotate secrets
   - Set `refreshInterval` appropriately in ExternalSecrets
   - Implement application-level rotation logic

## Integration with ArgoCD

See `apps/argocd/argocd/` for ArgoCD integration:
- ArgoCD can use ExternalSecrets for repository credentials
- ArgoCD can deploy applications that use ExternalSecrets
- Secrets are synced automatically by ESO

## Next Steps

- [ ] Move existing Kubernetes secrets to Vault
- [ ] Create namespace-specific SecretStores for each tenant
- [ ] Implement secret rotation policies
- [ ] Enable Vault audit logging
- [ ] Configure auto-unseal (for production)
- [ ] Set up Vault backups
- [ ] Document tenant secret management workflow

## References

- [Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [External Secrets Operator](https://external-secrets.io/)
- [Vault Policies](https://developer.hashicorp.com/vault/docs/concepts/policies)
