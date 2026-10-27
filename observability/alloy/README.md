# ForgeOps G10-C — Grafana Alloy Collector Architecture & Configuration

## 1. Overview
Grafana Alloy collects Pod logs from the G08 rehearsal environment and forwards them to the central Loki service. Alloy uses the Kubernetes API directly to tail logs, eliminating the need for privileged containers, root users, or host filesystem mounts.

## 2. Pinned Versions & Topology
- **Helm Chart**: `grafana/alloy` v1.14.3
- **App Version**: `v1.21.2`
- **Deployment Topology**: Single-replica `Deployment` (1 replica)
- **Namespace**: `forgeops-observability`
- **Scrape Method**: Kubernetes API (`loki.source.kubernetes`)

## 3. Scope & Labeling Boundaries
- **Target Filter**: Scoped strictly to namespace `forgeops-gitops-rehearsal` and pod label `app.kubernetes.io/name: forgetasks-rehearsal-api`.
- **Bounded Stream Labels**:
  - `namespace`: Kubernetes namespace (`forgeops-gitops-rehearsal`)
  - `container`: Container name (`forgetasks-api`)
  - `app`: Application name (`forgetasks-rehearsal-api`)
- **Cardinality Guard**: Dynamic Pod names (`pod`), request metadata (`correlationId`, `X-Request-ID`), user IDs, HTTP status codes, and timestamps are **NOT** indexed as Loki stream labels. They remain inside the raw ECS JSON log payload and are parsed dynamically via LogQL.

## 4. RBAC & Security Boundaries
- **ServiceAccount**: `alloy` in `forgeops-observability`.
- **Namespaced Role**: Created strictly in `forgeops-gitops-rehearsal` granting `get`, `list`, `watch` on `pods` and `pods/log`.
- **Zero Cluster-Wide Privileges**: No ClusterRole or ClusterRoleBinding is created.
- **Zero Secret Access**: Alloy cannot read ConfigMaps or Secrets.
- **Isolation**: Alloy has no access to `forgeops-dev` (G06), databases, or control-plane namespaces.

## 5. Resource Budget
- **CPU**: Request `50m`, Limit `200m`
- **Memory**: Request `64Mi`, Limit `128Mi`
