# Removing Users

How to offboard a tenant user and revoke access.

## Quick Steps

### 1. Remove from Access Policy

Edit the access policy:

```bash
vim docs/omni-access-policy.yaml
```

Remove user from their team's rule:

```yaml
rules:
  - users:
      - alice@example.com
      # - olduser@example.com  <- Remove or comment out
    kubernetes:
      impersonate:
        groups:
          - team-a-admins
    role: Reader
```

### 2. Apply Changes

```bash
omnictl apply -f docs/omni-access-policy.yaml
```

### 3. Verify Removal

Test that user no longer has access:

```bash
kubectl auth can-i get pods --as=olduser@example.com --as-group=team-a-admins -n team-a
# Should return: no
```

## Result

- User immediately loses namespace access
- Existing kubeconfig will return "Forbidden" errors
- No kubectl cleanup needed (group-based RBAC)

## Optional: Remove from Omni

If the user no longer needs any Omni access:

1. Go to Omni Dashboard → **Users**
2. Find the user
3. Click **Remove**

## See Also

- **[Adding Users](adding-users.md)** - Onboarding workflow
