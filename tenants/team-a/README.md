# team-a

To update PostgreSQL password:

```shell
export VAULT_TOKEN="hvs.xxxxxxx"
kubectl exec -n vault vault-0 -- vault kv put kv/team-a/postgres \
    POSTGRES_USER="team-a" \
    POSTGRES_PASSWORD="team-a"
```
