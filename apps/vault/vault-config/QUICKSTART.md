# Vault Quick Start

## TL;DR

```bash
# 1. Port forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &

# 2. Set environment variables
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="$MY_VAULT_TOKEN"  # From vault.env pragma: allowlist secret

# 3. Run setup
cd apps/vault/vault-config
./setup-vault.sh

# 4. Test with example
kubectl apply -f external-secret-example-argocd.yaml
kubectl get externalsecret -n argocd
kubectl get secret -n argocd argocd-secret
```

## What Gets Configured

### 1. Kubernetes Auth Method
- Allows pods to authenticate using their ServiceAccount tokens
- No need to manually manage Vault tokens for applications

### 2. Policies (RBAC for Vault)
| Policy | Access |
|--------|--------|
| `argocd` | Read `secret/data/argocd/*` and `secret/data/apps/*` |
| `apps` | Read `secret/data/apps/<namespace>/*` |
| `tenants` | Full access to `secret/data/tenants/<namespace>/*` |
| `external-secrets` | Read all secrets (for ESO) |

### 3. Kubernetes Auth Roles
| Role | ServiceAccount | Namespace | Policy |
|------|----------------|-----------|--------|
| `argocd` | argocd-* | argocd | argocd |
| `external-secrets` | external-secrets* | external-secrets | external-secrets |
| `app` | default | * | apps |
| `tenant` | default | team-* | tenants |

### 4. Example Secrets
- `secret/argocd/admin` - Admin password
- `secret/apps/my-app/database` - Database credentials
- `secret/tenants/team-a/config` - Tenant configuration

### 5. SecretStores
- **ClusterSecretStore** (`vault-backend`) - Cluster-wide access
- **SecretStore** (`vault-backend` in argocd namespace) - ArgoCD-specific

## Common Tasks

### Add a Secret for an App

```bash
# 1. Create secret in Vault
vault kv put secret/apps/my-namespace/app-config \
  api_key="secret123" \
  database_password="db-pass"

# 2. Create ExternalSecret (save to file and apply)
# See external-secret-example-app.yaml for template

# 3. Verify
kubectl get secret -n my-namespace app-config
```

### Rotate a Secret

```bash
# 1. Update in Vault
vault kv put secret/apps/my-namespace/app-config \
  api_key="new-secret456" \
  database_password="new-db-pass"

# 2. Wait for ESO to sync (based on refreshInterval)
# OR force immediate sync by deleting the K8s secret
kubectl delete secret -n my-namespace app-config

# 3. ESO recreates it immediately with new values
kubectl get secret -n my-namespace app-config
```

## Troubleshooting

### ExternalSecret shows "SecretSyncedError"

```bash
# Check logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check ExternalSecret status
kubectl describe externalsecret -n NAMESPACE NAME

# Verify Vault path exists
vault kv get secret/apps/my-namespace/app-config
```

## File Reference

| File | Purpose |
|------|---------|
| `setup-vault.sh` | Master setup script (runs all steps) |
| `01-enable-k8s-auth.sh` | Enable Kubernetes auth method |
| `02-create-policies.sh` | Create Vault policies |
| `03-create-roles.sh` | Create Kubernetes auth roles |
| `04-populate-secrets.sh` | Create example secrets |
| `cluster-secret-store.yaml` | ClusterSecretStore for ESO |
| `secret-store-argocd.yaml` | SecretStore for ArgoCD |
| `external-secret-example-argocd.yaml` | Example ExternalSecrets |
| `external-secret-example-app.yaml` | App ExternalSecret templates |
| `README.md` | Full documentation |

## Next Steps

1. Run `./setup-vault.sh`
2. Test with example ExternalSecrets
3. Migrate existing secrets to Vault
4. Update applications to use ExternalSecrets
5. Configure secret rotation
6. Enable Vault audit logging

## Security Notes

⚠️ **The root token in `vault.env` is sensitive!**
- Don't commit it to Git
- Rotate it after initial setup
- Use limited-privilege tokens for day-to-day operations

⚠️ **Unseal keys are critical!**
- Store in a secure location
- Required to unseal Vault after restart
- Consider auto-unseal for production

For more details, see [README.md](README.md)
