# To Do

## Must Have

- [X] Add `external-secrets` operator (ESO)
- [ ] Implement `kyverno` policies for security and compliance.
- [ ] Write docs on multi-tenancy/namespace-as-a-service.
- [ ] Kubernetes RBAC (maybe use Omni RBAC?)
- [ ] Cilium network policies for namespaces
- [ ] Vault configuration
- [ ] Vault policies

## Should Have

- [ ] Set up monitoring and alerting for the cluster.
- [X] Cilium ingress (Gateway API + HTTPRoute for ArgoCD).
- [ ] Move secrets to Vault and integrate with ESO.
- [ ] Document cluster architecture and configurations.
- [X] App that demo's using a containerized Microsoft SQL Server. (tenants/team-b/app/mssql.yaml)
- [X] App that demo's using PostgreSQL. (tenants/team-a/app/postgres.yaml)

## Could Have

- [ ] Set up backup and disaster recovery plan
- [ ] Implement CI/CD pipeline for automated deployments

## Won't Have

- [ ] Add service mesh (e.g., Istio, Linkerd) at this time]
