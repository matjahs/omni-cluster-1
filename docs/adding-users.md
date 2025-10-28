# Adding Users

Step-by-step guide to onboard a new tenant user.

## Prerequisites

- Omni dashboard access
- kubectl access to the cluster
- User's email address

## Steps

### 1. Create Omni User

In the Omni Dashboard:
1. Navigate to **Users**
2. Click **Add User**
3. Enter email: `newuser@example.com`
4. Save

### 2. Add to Access Policy

Edit the access policy:

```bash
vim docs/omni-access-policy.yaml
```

Add user to the appropriate team:

```yaml
rules:
  # Team A members
  - users:
      - alice@example.com
      - charlie@example.com
      - newuser@example.com  # <- Add here
    kubernetes:
      impersonate:
        groups:
          - team-a-admins
    role: Reader
```

### 3. Apply Changes

```bash
omnictl apply -f docs/omni-access-policy.yaml
```

### 4. Notify User

Send the user:
1. Omni dashboard URL
2. Instructions to download kubeconfig:

```bash
# Via Omni CLI
omnictl kubeconfig talos-default > ~/.kube/config

# Or via Omni Web UI
# Clusters → talos-default → Download Kubeconfig
```

### 5. User Tests Access

User verifies they can access their namespace:

```bash
# Should work
kubectl get pods -n team-a

# Should fail (other namespaces)
kubectl get pods -n team-b
```

## Done!

The user now has access to their assigned namespace. No additional kubectl commands needed!

## See Also

- **[Removing Users](removing-users.md)** - Offboarding workflow
- **[User Roles](user-roles.md)** - Available permission levels
- **[Troubleshooting](troubleshooting.md)** - Common issues
