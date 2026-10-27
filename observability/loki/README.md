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
