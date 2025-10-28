# To Do

## Must Have

- [X] Add `external-secrets` operator (ESO)
- [ ] Implement `kyverno` policies for security and compliance.
- [X] Write docs on multi-tenancy/namespace-as-a-service.
- [X] Kubernetes RBAC (maybe use Omni RBAC?)
- [ ] Cilium network policies for namespaces
- [ ] Vault configuration
- [ ] Vault policies

## Should Have

- [X] Set up monitoring and alerting for the cluster.
- [X] Cilium ingress (Gateway API + HTTPRoute for ArgoCD).
- [X] Move secrets to Vault and integrate with ESO.
- [X] Document cluster architecture and configurations.
- [X] App that demo's using a containerized Microsoft SQL Server. (tenants/team-b/app/mssql.yaml)
- [X] App that demo's using PostgreSQL. (tenants/team-a/app/postgres.yaml)

## Could Have

- [ ] Set up backup and disaster recovery plan
- [X] Implement CI/CD pipeline for automated deployments

## Won't Have

- [ ] Add service mesh (e.g., Istio, Linkerd) at this time.
