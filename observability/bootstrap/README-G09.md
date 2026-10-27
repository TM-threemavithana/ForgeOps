# ForgeOps G09 — Monitoring Bootstrap Runbook

Status: CANDIDATE — NOT APPROVED FOR DEPLOYMENT

## Versions and provenance

- Helm chart: kube-prometheus-stack 92.11.0
- Chart OCI source: ghcr.io/prometheus-community/charts
- Operator version: v0.94.1
- Target cluster: kind-forgeops
- Monitoring namespace: forgeops-observability
- CRDs: 10 monitoring.coreos.com definitions

CRD bundle checksum (SHA-256):

756a46e828bee619fb34c4b0aebc431278ae0a00127345c3c7e33a96a40b5656

## Ownership

Bootstrap-owned:
- Monitoring CRDs
- forgeops-observability Namespace
- Operator cluster-reader RBAC
- G08 rehearsal metrics-reader RBAC
- Grafana administrator credential provisioning
- Argo CD OCI repository registration
- G09 AppProject and Application registration

G09 Application-owned:
- Prometheus Operator and monitoring workloads
- Prometheus and Alertmanager custom resources
- Grafana
- G09 namespaced RBAC
- ForgeTasks ServiceMonitor

Protected and never adopted:
- G06 namespace, database and PVC
- G08 namespace, database and PVC
- Existing G08 AppProject and Application

## Approved deployment order — execution pending

1. Review and merge the G09 feature branch into master.
2. Verify the selected Kind cluster and baseline G06/G08 health.
3. Verify the pinned CRD checksum and confirm existing CRD ownership.
4. Install the ten CRDs using a separately reviewed
   server-side apply procedure, then wait for Established conditions.
5. Create forgeops-observability using the bootstrap namespace manifest.
6. Install reviewed cluster-reader and G08 read-only discovery RBAC.
7. Provision g09-grafana-admin in forgeops-observability out of band.
   Never commit credentials, echo passwords, or store them in shell history.
8. Register and verify the OCI Helm repository in Argo CD using
   type=helm and enableOCI=true.
9. Register the G09 AppProject and manual-sync Application.
10. Inspect the rendered Application manifest and validate RBAC.
11. Manually sync only after all readiness checks pass.
12. Validate Pod readiness, metrics targets, storage, and G06/G08 health.

## Safety rules

- Never run terraform destroy for this gate.
- Never delete existing Namespaces, StatefulSets, PVCs or PVs.
- Never prune or delete monitoring CRDs during routine cleanup.
- Do not enable Argo CD automatic pruning.
- Do not grant the Operator cross-namespace write permissions.
- Do not force CRD field ownership conflicts without review.
- Do not deploy from an unmerged feature branch.
- No monitoring deployment is authorized by this document.

## Acceptance requirements

- Prometheus scrapes /actuator/prometheus successfully.
- Grafana can query the Prometheus datasource.
- Alertmanager is healthy.
- A G09-owned alert transitions Pending -> Firing -> Resolved.
- Custom Operator RBAC passes Kubernetes authorization checks.
- No unwanted cross-namespace permissions are granted.
- G06 and G08 stay healthy and protected.
- GitOps Application reports Synced / Healthy.

G09 is not accepted until these checks pass.
