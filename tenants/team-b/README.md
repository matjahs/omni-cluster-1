# team-b

Team B demonstrates a simple SQL Server workload that relies on a manually
managed Kubernetes `Secret` instead of Vault/External Secrets.

To update the SA password that backs the `mssql-login` secret, either edit
`tenants/team-b/app/secret.yaml` directly with a new base64-encoded value or
recreate the secret with `kubectl`:

```shell
kubectl create secret generic mssql-login \
  --namespace team-b \
  --from-literal=MSSQL_SA_PASSWORD="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml > tenants/team-b/app/secret.yaml
```

The SQL Server pod uses the `mssql-data` PersistentVolumeClaim, which expects a
`longhorn` storage class to be available in the cluster.
