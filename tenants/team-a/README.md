# team-a

## User Access

### Alice (`alice@matjah.dev`)

Alice has been granted admin access to the `team-a` namespace via Omni RBAC.

#### Setup Instructions for Alice:

1. **Set Omni Role** (Administrator does this):
   - In Omni Dashboard → Users → `alice@matjah.dev`
   - Set Role: **Reader**

2. **Download Kubeconfig**:
   ```bash
   # Via Omni CLI
   omnictl kubeconfig talos-default > ~/.kube/config-team-a

   # OR download via Omni Web UI:
   # Clusters → talos-default → "Download Kubeconfig"
   ```

3. **Set Kubeconfig Environment**:
   ```bash
   export KUBECONFIG=~/.kube/config-team-a
   ```

4. **Verify Access**:
   ```bash
   # These should work (team-a namespace)
   kubectl get pods -n team-a
   kubectl get all -n team-a
   kubectl create deployment test -n team-a --image=nginx

   # These should fail (no access)
   kubectl get pods -n team-b
   kubectl get nodes
   ```

#### Alice's Permissions:
- **Full admin rights** in `team-a` namespace
- Can create/delete/modify all resources (pods, deployments, services, secrets, etc.)
- **No access** to other namespaces or cluster-level resources

#### RBAC Configuration:
- RoleBinding: [alice-rolebinding.yaml](resources/alice-rolebinding.yaml)
- Role: [team-a-admin-role.yaml](resources/team-a-admin-role.yaml)

---

## Vault Integration

To update PostgreSQL password:

```shell
export VAULT_TOKEN="hvs.xxxxxxx"
kubectl exec -n vault vault-0 -- vault kv put kv/team-a/postgres \
    POSTGRES_USER="team-a" \
    POSTGRES_PASSWORD="team-a"
```
