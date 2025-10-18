# Kubernetes Secret to Vault Migration Guide

This guide walks through migrating existing Kubernetes secrets to HashiCorp Vault.

## Quick Demo - Migrate ArgoCD Initial Admin Secret

### Step 1: View the Existing Secret

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o yaml
```

### Step 2: Extract and Decode the Password

```bash
# Get the password
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### Step 3: Store in Vault

```bash
# Set Vault connection (if not already set)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="<your-vault-token>"

# Store the secret
DECODED_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

vault kv put secret/argocd/initial-admin \
  password="$DECODED_PASSWORD"
```

### Step 4: Create ExternalSecret

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-initial-admin-from-vault
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: argocd-initial-admin-from-vault
    creationPolicy: Owner
    template:
      type: Opaque
  dataFrom:
    - extract:
        key: argocd/initial-admin
```

### Step 5: Apply and Verify

```bash
# Apply the ExternalSecret
kubectl apply -f external-secret.yaml

# Check status
kubectl get externalsecret -n argocd argocd-initial-admin-from-vault

# Verify the secret was created
kubectl get secret -n argocd argocd-initial-admin-from-vault

# Compare passwords
echo "Original:"
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

echo -e "\nFrom Vault:"
kubectl get secret -n argocd argocd-initial-admin-from-vault \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Migration Patterns

### Pattern 1: Simple Secret (Single Key-Value)

```bash
# 1. Extract
VALUE=$(kubectl get secret -n ns secret-name -o jsonpath='{.data.key}' | base64 -d)

# 2. Store in Vault
vault kv put secret/path key="$VALUE"

# 3. Create ExternalSecret
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: secret-name
  namespace: ns
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: secret-name
  dataFrom:
    - extract:
        key: path
EOF
```

### Pattern 2: Multi-Key Secret

```bash
# 1. Extract all keys
kubectl get secret -n ns secret-name -o json | \
  jq -r '.data | to_entries[] | "\(.key)=\(.value | @base64d)"'

# 2. Store in Vault
vault kv put secret/apps/myapp/config \
  key1="value1" \
  key2="value2" \
  key3="value3"

# 3. Create ExternalSecret
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: secret-name
  namespace: ns
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: secret-name
  dataFrom:
    - extract:
        key: apps/myapp/config
EOF
```

### Pattern 3: Database Credentials with Connection String

```bash
# 1. Store individual fields in Vault
vault kv put secret/apps/myapp/database \
  host="postgres.default.svc" \
  port="5432" \
  database="mydb" \
  username="dbuser" \
  password="secretpass"

# 2. Create ExternalSecret with template
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-config
  namespace: myapp
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: database-config
    template:
      data:
        # Individual fields
        DB_HOST: "{{ .host }}"
        DB_PORT: "{{ .port }}"
        DB_NAME: "{{ .database }}"
        DB_USER: "{{ .username }}"
        DB_PASSWORD: "{{ .password }}"
        # Computed connection string
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/{{ .database }}"
  data:
    - secretKey: host
      remoteRef: {key: apps/myapp/database, property: host}
    - secretKey: port
      remoteRef: {key: apps/myapp/database, property: port}
    - secretKey: database
      remoteRef: {key: apps/myapp/database, property: database}
    - secretKey: username
      remoteRef: {key: apps/myapp/database, property: username}
    - secretKey: password
      remoteRef: {key: apps/myapp/database, property: password}
EOF
```

---

## Vault Path Structure Best Practices

```
secret/
├── argocd/               # Application-specific
│   ├── admin/
│   ├── server/
│   └── repo/
├── apps/
│   └── <namespace>/      # Namespace isolation
│       └── <app-name>/
│           ├── database/
│           ├── api-keys/
│           └── certificates/
└── tenants/
    └── <team-name>/      # Tenant isolation
        └── <resource>/
```

---

## Migration Checklist

- [ ] Export existing K8s secret
- [ ] Decode secret values
- [ ] Store in Vault with proper path structure
- [ ] Create ExternalSecret resource
- [ ] Apply ExternalSecret
- [ ] Verify secret is synced (Status: SecretSynced)
- [ ] Verify secret data matches original
- [ ] Test application still works
- [ ] (Optional) Delete original K8s secret
- [ ] Document the migration

---

## Troubleshooting

### Secret not syncing

```bash
# Check ExternalSecret status
kubectl describe externalsecret -n <namespace> <name>

# Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# Verify Vault path exists
vault kv get secret/<path>

# Check SecretStore is valid
kubectl get secretstore -n <namespace> -o yaml
```

### Values don't match

```bash
# Compare directly
echo "Original:"
kubectl get secret -n ns original-secret -o jsonpath='{.data.key}' | base64 -d

echo "From Vault:"
kubectl get secret -n ns vault-synced-secret -o jsonpath='{.data.key}' | base64 -d

# Check Vault
vault kv get -field=key secret/path
```

---

## Security Notes

⚠️ **Important:**
- Never commit decoded secrets to Git
- Clear terminal history after working with secrets: `history -c`
- Use short-lived Vault tokens when possible
- Rotate secrets after migration
- Enable Vault audit logging

---

## Additional Resources

- Full documentation: `README.md`
- Quick reference: `QUICKSTART.md`
- Example ExternalSecrets: `external-secret-example-*.yaml`
