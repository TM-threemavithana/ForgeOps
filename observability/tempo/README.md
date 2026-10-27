# ForgeOps G11 — Tempo Distributed Tracing Architecture & Configuration

## 1. Overview
Grafana Tempo provides high-scale, cost-effective distributed trace storage for the ForgeOps platform. Under G11, Tempo is deployed in a single-binary monolithic topology suited for local lab development while adhering strictly to resource, security, and GitOps boundaries.

## 2. Pinned Versions & Topology
- **Helm Chart**: `grafana/tempo` v1.24.4
- **App Version**: `2.9.0`
- **Deployment Topology**: `monolithic` StatefulSet (single replica)
- **Namespace**: `forgeops-observability`
- **Storage Backend**: Local filesystem block storage on Kind `standard` storage class
- **PVC Allocation**: 2 GiB bounded PersistentVolumeClaim (`tempo-0`)
- **Tracing Pipeline**: `ForgeTasks API (rehearsal)` -> `Alloy OTLP Receiver (4317/4318)` -> `Tempo OTLP gRPC (4317)`

## 3. Storage & Retention Architecture
- **Trace Storage**: Local filesystem (`/var/tempo/traces`)
- **Write-Ahead Log (WAL)**: Local filesystem (`/var/tempo/wal`)
- **Retention Period**: 24 hours (`tempo.retention: 24h`)
- **Compaction**: Native background block compaction to local disk
- **Multitenancy**: Disabled (`multitenancyEnabled: false`)

## 4. Resource Budget
- **CPU**: Request `50m`, Limit `500m`
- **Memory**: Request `128Mi`, Limit `512Mi`

## 5. Security & Boundary Hardening
- **No Public Ingress**: Tempo services bind internally only within `forgeops-observability`:
  - `tempo.forgeops-observability.svc.cluster.local:3200` (HTTP query API & Prometheus metrics)
  - `tempo.forgeops-observability.svc.cluster.local:4317` (OTLP gRPC)
  - `tempo.forgeops-observability.svc.cluster.local:4318` (OTLP HTTP)
- **No In-Container Tools Dependency**: Liveness and readiness probes query native HTTP endpoints (`/ready`).
- **No Cloud Dependencies**: Cloud object storage (S3/GCS/Azure Blob), Kafka, and Jaeger UI proxies are explicitly disabled.

## 6. Querying & Grafana Integration
- **Direct Trace Retrieval via HTTP API**:
  ```bash
  # Retrieve trace JSON by 32-character hex TraceId
  curl -s http://127.0.0.1:13200/api/traces/<traceId>
  ```
- **Grafana Tempo Datasource**:
  - Configured via sidecar ConfigMap `g11-grafana-datasource-tempo` in `forgeops-observability`.
  - Seamless Trace-to-Logs navigation (`tracesToLogsV2`) configured to link trace spans directly to matching ECS JSON log lines in Loki using `{app="rehearsal-api"} |= "${__trace.id}"`.

## 7. Storage Provisioning Nuance & Operational Safeguards
- **Local-Path Provisioner Behavior**: In Kind, the default `standard` storage class utilizes Rancher `local-path-provisioner`. The `2Gi` PVC declaration requests bounded capacity without hard kernel quota enforcement.
- **Operational Safeguards**:
  1. **Block Compaction & Retention Sweeps**: Tempo runs background retention sweeps deleting blocks exceeding 24 hours.
  2. **Bounded Ingestion**: In the local rehearsal environment, traces are generated only by synthetic probes and rehearsal traffic.
  3. **Capacity Monitoring**: Operators can inspect effective filesystem disk usage safely via `kubectl exec -n forgeops-observability tempo-0 -- df -h /var/tempo`.

## 8. Non-Destructive Rollback & Reconciliation Runbook
- **Zero Automatic Destruction**: Rollback never automatically deletes PVCs, StatefulSets, persistent data, or Argo CD Applications.
- **Operator-Approved Non-Destructive Reconciliation**:
  1. **Halt Trace Export**: Revert application configuration or scale Alloy's receiver to cease forwarding traces.
  2. **Freeze Tracing Service**: If Tempo requires rollback or maintenance, scale the StatefulSet to 0 (`kubectl scale statefulset tempo -n forgeops-observability --replicas=0`). This preserves the PVC and all existing trace blocks intact.
  3. **Datasource Decoupling**: Delete or disable the `g11-grafana-datasource-tempo` ConfigMap to revert Grafana cleanly to its G10 baseline without restarting the Grafana pod.
  4. **Data Deletion**: Any persistent data removal or PVC deletion requires explicit, separate operator approval following full lab evidence archival.
