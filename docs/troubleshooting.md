# Troubleshooting

Common issues and solutions.

## User Can't Access Their Namespace

### Symptoms
```bash
kubectl get pods -n team-a
# Error: pods is forbidden
```

### Solutions

**1. Check Access Policy**
```bash
omnictl get accesspolicy access-policy -o yaml | grep -A10 "user@example.com"
```

**2. Verify RoleBinding exists**
```bash
kubectl get rolebinding -n team-a
# Should see: team-a-admins-binding
```

**3. Test permissions**
```bash
kubectl auth can-i get pods --as=user@example.com --as-group=team-a-admins -n team-a
# Should return: yes
```

**4. User downloads fresh kubeconfig**
```bash
omnictl kubeconfig talos-default > ~/.kube/config --force
```

---

## User Sees Other Namespaces

### Symptoms
```bash
kubectl get pods -n team-b
# Shows pods (unexpected?)
```

### Explanation

**This is expected behavior!** See [Namespace Isolation](namespace-isolation.md) for details.

**Key points:**
- Users can VIEW other namespaces
- Users CANNOT MODIFY other namespaces
- This is industry-standard Kubernetes multi-tenancy

**Test modification (should fail):**
```bash
kubectl create deployment test -n team-b --image=nginx
# Error: deployments.apps is forbidden
```

---

## Access Policy Changes Not Taking Effect

### Solutions

**1. Wait 1-2 minutes** (Omni caches policies)

**2. User downloads new kubeconfig**
```bash
omnictl kubeconfig talos-default > ~/.kube/config
```

**3. Verify policy was applied**
```bash
omnictl get accesspolicy access-policy -o jsonpath='{.metadata.version}'
# Version number should have incremented
```

---

## Cannot Download Kubeconfig

### Symptoms
```bash
omnictl kubeconfig talos-default
# Error: Forbidden
```

### Solutions

**Check Omni role:**
- User needs at least `Reader` role in Access Policy
- `None` role prevents kubeconfig download

**Fix:**
```yaml
# In docs/omni-access-policy.yaml
- users:
    - user@example.com
  role: Reader  # Not "None"
```

---

## Group RoleBinding Not Working

### Symptoms
User has Access Policy entry but still can't access namespace.

### Solutions

**1. Verify RoleBinding references correct group**
```bash
kubectl get rolebinding team-a-admins-binding -n team-a -o yaml
# subjects[].name should match Access Policy impersonation group
```

**2. Verify Role exists**
```bash
kubectl get role team-a-admin -n team-a
```

**3. Check group name matches exactly**
```yaml
# Access Policy
impersonate:
  groups:
    - team-a-admins

# RoleBinding
subjects:
- kind: Group
  name: team-a-admins  # Must match exactly!
```

---

## Need More Help?

1. Check [Namespace Isolation](namespace-isolation.md) for expected behavior
2. Review [Access Policies](access-policies.md) for configuration details
3. See [Configuration Files](configuration-files.md) for file locations
