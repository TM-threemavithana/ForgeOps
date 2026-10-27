# ForgeOps G10-C — Loki Architecture & Configuration

## 1. Overview
Loki provides lightweight, scalable log aggregation for the ForgeOps platform. Under G10-C, Loki is deployed in a single-binary monolithic topology suited for local lab development while adhering strictly to resource, security, and GitOps boundaries.

## 2. Pinned Versions & Topology
- **Helm Chart**: `grafana/loki` v6.27.0
- **App Version**: `3.4.2`
- **Deployment Topology**: `SingleBinary` (monolithic single replica)
- **Namespace**: `forgeops-observability`
- **Storage Backend**: Local filesystem persistence on Kind `standard` storage class
- **PVC Allocation**: 2 GiB bounded PersistentVolumeClaim (`loki-single-binary-0`)

## 3. Storage & Retention Architecture
- **Index Store**: TSDB (`store: tsdb`, `schema: v13`, `period: 24h`)
- **Object Store**: Local filesystem (`/var/loki/chunks`, `/var/loki/rules`, `/var/loki/admin`)
- **Retention Period**: 24 hours (`retention_period: 24h`, `reject_old_samples_max_age: 24h`)
- **Compactor**: Enabled with `retention_enabled: true`, `delete_request_store: filesystem`, `compactor_ring.kvstore.store: inmemory`
- **Replication Factor**: 1

## 4. Resource Budget
- **CPU**: Request `100m`, Limit `500m`
- **Memory**: Request `256Mi`, Limit `512Mi`

## 5. Security & Boundary Hardening
- **No Public Ingress**: Loki service binds internally only (`http://loki.forgeops-observability.svc.cluster.local:3100`).
- **No Cluster-Wide Privileges**: `rbac.namespaced: true` suppresses all default ClusterRoles and ClusterRoleBindings.
- **No External Dependencies**: Distributed gateways, MinIO object store, and memcached caching components are explicitly disabled.

## 6. LogQL Queries
- **Rehearsal API Stream**:
  ```logql
  {app="forgetasks-rehearsal-api"}
  ```
- **Filter by MDC Correlation ID (ECS JSON)**:
  ```logql
  {app="forgetasks-rehearsal-api"} | json | correlationId = "your-uuid-here"
  ```
- **Filter by Error Level**:
  ```logql
  {app="forgetasks-rehearsal-api"} | json | log_level = "ERROR" or log_level = "WARN"
  ```

## 7. Storage Provisioning Nuance & Operational Safeguards
- **Local-Path Provisioner Behavior**: In Kind, the default `standard` storage class utilizes Rancher `local-path-provisioner`. In this environment, the `2Gi` PVC declaration is a scheduler capacity request and declarative bound, but does **not** enforce a hard OS-level directory quota on the host filesystem.
- **Operational Safeguards**:
  1. **Compactor Sweeps**: Compactor retention is explicitly active (`retention_enabled: true`, `retention_period: 24h`), scheduling regular deletion sweeps of chunks exceeding 24 hours.
  2. **Ingestion Invariants**: Scraping is strictly isolated to the single rehearsal API workload with bounded labels, keeping ingestion rates below ~50 KB/hour in development.
  3. **Capacity Monitoring**: Operators can inspect effective filesystem disk usage safely via `kubectl exec -n forgeops-observability loki-0 -- df -h /var/loki`.

## 8. Non-Destructive Rollback & Reconciliation Runbook
- **Zero Automatic Destruction**: Rollback never automatically deletes PVCs, StatefulSets, persistent data, or Argo CD Applications.
- **Operator-Approved Non-Destructive Reconciliation**:
  1. **Halt Ingestion**: Scale the Alloy deployment to 0 (`kubectl scale deployment alloy -n forgeops-observability --replicas=0`) to stop streaming immediately without affecting any application workloads.
  2. **Freeze Logging Service**: If Loki requires rollback or maintenance, scale the StatefulSet to 0 (`kubectl scale statefulset loki -n forgeops-observability --replicas=0`). This preserves the `loki-single-binary-0` PVC, index files, and all existing chunks intact.
  3. **Datasource Decoupling**: Delete or disable the `g10-grafana-datasource-loki` ConfigMap to revert Grafana cleanly to its G09 Prometheus-only baseline without restarting the Grafana pod.
  4. **Data Deletion**: Any persistent data removal or PVC deletion requires explicit, separate operator approval following full lab evidence archival.

