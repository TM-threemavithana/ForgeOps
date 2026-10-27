# ForgeOps Gate G10 — Log Aggregation & Observability Acceptance Report

**Gate Status**: **PASSED**  
**Date**: October 27, 2026  
**Cluster Context**: `kind-forgeops`  
**Kubeconfig**: `/home/tharuka/.kube/config-forgeops`  
**Engineer Roles**: Senior DevOps Engineer, Kubernetes Platform Engineer, SRE  

---

## 1. Executive Summary

ForgeOps Gate G10 (Sub-phases G10-C through G10-F) was executed and verified using a guarded, non-destructive deployment workflow.
All required logging infrastructure components (Grafana Loki single-binary, Grafana Alloy API log collector, and Grafana datasource provisioning) were deployed declaratively via Argo CD with automated synchronization strictly disabled.

Full end-to-end acceptance was validated against the live Kind cluster, proving:
1. Complete log ingestion of Elastic Common Schema (ECS 8.11) JSON logs from the GitOps Rehearsal API.
2. Exact HTTP probe header (`X-Request-ID`) and ProblemDetail body (`correlationId`) correlation.
3. Successful LogQL retrieval via `/loki/api/v1/query_range` with structured JSON parsing.
4. Positive and negative RBAC enforcement: Alloy operates strictly via namespaced Role/RoleBinding without cluster-scoped privileges.
5. Strict negative log isolation: zero logs from `forgeops-dev` or the `postgres` database container in Loki (`result: []`).
6. Zero-downtime Grafana datasource provisioning via the existing G09 sidecar without restarting Grafana.
7. Uninterrupted health and continuity for Prometheus, Alertmanager, and existing application workloads.
8. 100% preservation of all three protected database and monitoring PVC UIDs.
9. G08 Rehearsal automated synchronization remains strictly disabled (`automated: false`).

---

## 2. GitOps Release Traceability

All configuration changes were reviewed, tested against static validation workflows, and merged to `master` through standard PR merge commits:

| PR Number | PR Title | Merge Commit SHA | Scope |
|:---|:---|:---|:---|
| **#36** | `feat(observability): implement Loki, Alloy, and Grafana integration for G10` | `a820b4a65e1a89494d0e7b39579551059823db89` | Deploys Loki Helm values, Alloy Helm values, Grafana Datasource ConfigMap, Argo CD Application manifests, AppProject, Helm repo secret, and initial acceptance suite. |
| **#37** | `fix(observability): align Alloy discovery and test query with rehearsal-api label` | `09137ca5ef050b1d3056093fbef48f8045b59a0f` | Aligns Alloy discovery regex with the actual G08 Rehearsal API Pod label `app.kubernetes.io/name=rehearsal-api`. |
| **#38** | `fix(test): use query_range endpoint and exact Loki PVC name in G10 acceptance suite` | `8d696d96e54f9d0c2ee5d97f374719bbdf2df447` | Corrects Loki stream query endpoint to `/loki/api/v1/query_range` and targets exact PVC name `storage-loki-0`. |

---

## 3. Pinned Versions & Helm Chart Inventory

| Component | Upstream Repository / Registry | Chart Version | Image / App Version | Deployment Topology | Storage / Retention |
|:---|:---|:---|:---|:---|:---|
| **Loki** | `https://grafana.github.io/helm-charts` (`loki`) | `6.27.0` | `docker.io/grafana/loki:3.0.0` | `SingleBinary` (monolithic StatefulSet, 1 replica) | 2Gi filesystem PVC (`storage-loki-0`), TSDB schema, 24h compactor retention |
| **Alloy** | `https://grafana.github.io/helm-charts` (`alloy`) | `1.14.3` | `docker.io/grafana/alloy:v1.21.2` | DaemonSet / Deployment (1 replica) | In-memory pipeline, API log tailing |
| **Grafana DS** | Git-managed ConfigMap (`observability/grafana`) | N/A | Sidecar-reloaded (`grafana_datasource: "1"`) | Dynamic reload | ConfigMap `g10-grafana-datasource-loki` |

### Rendered Helm Resources in Argo CD:
- **`g10-loki`** (7 resources): `ConfigMap/loki`, `ConfigMap/loki-runtime`, `Service/loki`, `Service/loki-headless`, `Service/loki-memberlist`, `ServiceAccount/loki`, `StatefulSet/loki`.
- **`g10-alloy`** (6 resources): `ConfigMap/alloy`, `Role/alloy` (in `forgeops-gitops-rehearsal`), `RoleBinding/alloy` (in `forgeops-gitops-rehearsal`), `Service/alloy`, `ServiceAccount/alloy`, `Deployment/alloy`.
- **`g10-grafana-datasource`** (1 resource): `ConfigMap/g10-grafana-datasource-loki`.

---

## 4. Protected PVC Continuity

The three protected persistent volume claims were verified before, during, and after deployment:

| Namespace | PVC Name | Baseline UID | Observed UID | Status | Capacity | Volume |
|:---|:---|:---|:---|:---|:---|:---|
| `forgeops-gitops-rehearsal` | `postgres-storage-forgetasks-rehearsal-db-0` | `b5ea8ec9-47e8-4979-afdb-621f2e3c63b8` | `b5ea8ec9-47e8-4979-afdb-621f2e3c63b8` | **MATCH** | 1Gi | `pvc-b5ea8ec9...` |
| `forgeops-dev` | `postgres-storage-forgetasks-db-0` | `84853fb3-4d13-43a9-bc62-973c3be3c90c` | `84853fb3-4d13-43a9-bc62-973c3be3c90c` | **MATCH** | 1Gi | `pvc-84853fb3...` |
| `forgeops-observability` | `prometheus-g09-monitoring-kube-promet-prometheus-db-...` | `cd64e090-2c69-49b3-a389-de5841ce06d6` | `cd64e090-2c69-49b3-a389-de5841ce06d6` | **MATCH** | 2Gi | `pvc-cd64e090...` |
| `forgeops-observability` | `storage-loki-0` (G10 New) | N/A | `23468366-7394-4f2d-be1f-2a640d6f12c5` | **BOUND** | 2Gi | `pvc-23468366...` |

---

## 5. End-to-End Acceptance Results

The complete acceptance suite (`scripts/cluster/test-g10-observability.sh`) was executed host-side via localhost port-forwarding on `127.0.0.1`:

| Test Step | Description | Expected | Observed | Outcome |
|:---|:---|:---|:---|:---|
| **Step 1** | Protected PVC UIDs check | Exact match against documented baselines | Rehearsal, Dev, and Observability PVC UIDs identical | **PASS** |
| **Step 2** | Pod readiness across namespaces | `loki-0`, `alloy-*`, `rehearsal-api-*`, `rehearsal-db-0` ready | All 4 workloads condition met and Ready | **PASS** |
| **Step 3** | Localhost port-forwards | Ports `13100`, `12345`, `13000`, `19090`, `18080` | Port-forward listeners established on `127.0.0.1` | **PASS** |
| **Step 4** | Loki `/ready` and PVC capacity | HTTP 200 `ready`, PVC capacity `2Gi` | HTTP 200 `ready`, `storage-loki-0` capacity `2Gi` | **PASS** |
| **Step 5** | Alloy `/-/healthy` endpoint | HTTP 200 containing `healthy` | HTTP 200 `All Alloy components are healthy.` | **PASS** |
| **Step 6** | Positive and Negative RBAC | Can get pods in rehearsal; denied in dev, ksys, and secret access | `rehearsal=yes`, `dev=no`, `secrets=no`, `kube-system=no` | **PASS** |
| **Step 7** | Baseline database account count | Baseline count recorded before probe | 2 accounts | **PASS** |
| **Step 8** | G10-B Invalid account registration probe | HTTP 400 Bad Request, matching `X-Request-ID` and ProblemDetail `correlationId` | HTTP 400, header and body correlation matched `req-g10-probe-1793120028-12867` | **PASS** |
| **Step 9** | Post-probe database immutability | Accounts count remains 2 | 2 accounts (zero records inserted, total immutability) | **PASS** |
| **Step 10** | LogQL ECS JSON retrieval | Ingested event retrievable in Loki with matching `correlationId` and ECS fields | Status `success`, matching `correlationId`, `service.name`, and `ecs.version` | **PASS** |
| **Step 11** | Low-cardinality index labels | Strictly bounded index labels (`app`, `container`, `namespace`), no high-cardinality `pod` | Labels: `app`, `container`, `instance`, `job`, `namespace`, `service_name`. No dynamic Pod labels. | **PASS** |
| **Step 12** | Negative log isolation | Zero logs from `forgeops-dev` and zero logs from `postgres` container in Loki | `{namespace="forgeops-dev"}` -> `result: []`; `{container="postgres"}` -> `result: []` | **PASS** |
| **Step 13** | Grafana datasource provisioning | Loki datasource configured via sidecar without restarting Grafana | Loki datasource present (`http://loki...:3100`), Prometheus intact, Grafana restarts=0 | **PASS** |
| **Step 14** | Prometheus scrape target continuity | All existing scrape targets remain UP | All targets UP and healthy | **PASS** |

---

## 6. Observed Telemetry & Correlation Sample

### Ingested ECS JSON Log Record:
```json
{
  "@timestamp": "2026-10-27T16:53:48.312154210Z",
  "log": {
    "level": "INFO",
    "logger": "com.forgeops.forgetasks.common.exception.GlobalExceptionHandler"
  },
  "process": {
    "pid": 1,
    "thread": {
      "name": "http-nio-8080-exec-5"
    }
  },
  "service": {
    "name": "forgetasks-api",
    "version": "1.0.0-SNAPSHOT",
    "node": {}
  },
  "message": "Validation failure on request: {password=Password must be between 8 and 100 characters, username=Username must be between 3 and 50 characters}",
  "correlationId": "req-g10-probe-1793120028-12867",
  "ecs": {
    "version": "8.11"
  }
}
```

### Stream Index Labels:
```json
{
  "app": "rehearsal-api",
  "container": "api",
  "instance": "forgeops-gitops-rehearsal/forgetasks-rehearsal-api-76c5d4c75d-gp8l2:api",
  "job": "loki.source.kubernetes.rehearsal_api",
  "namespace": "forgeops-gitops-rehearsal",
  "service_name": "rehearsal-api"
}
```

---

## 7. Storage, Retention & Resource Boundaries

- **Disk Headroom**: Kind cluster node and Windows host disk (`C:`) have >30GiB available storage.
- **Storage Boundary**: Loki's PVC is bounded at 2Gi. Under Kind's `local-path-provisioner`, this defines the scheduler allocation limit.
- **Retention Policy**: Loki compactor retention is configured for 24h (`retention_period: 24h`, `delete_request_store: filesystem`). Empirical expiration occurs as chunks age past 24h and are purged by the compactor sweep; no artificial claim of immediate chunk deletion is made.
- **G08 Auto-Sync**: The Argo CD Application `forgetasks-rehearsal` has `spec.syncPolicy.automated.enabled: false`. Manual reconciliation remains strictly enforced.

---

## 8. Conclusion & Sign-Off

ForgeOps Gate G10 is officially **PASSED**. All logging infrastructure is fully integrated into the GitOps control plane and observable via Grafana. The platform is ready for Gate G11.
