# ForgeOps Gate G11 — Distributed Tracing Acceptance & Verification Report

**Date:** 2026-10-28  
**Gate:** G11 — Distributed Tracing (Grafana Tempo & OpenTelemetry)  
**Status:** **PASSED**  
**Repository:** `TM-threemavithana/ForgeOps`  
**Target Cluster:** `kind-forgeops` (single-node local Kubernetes lab)  
**Kubeconfig:** `/home/tharuka/.kube/config-forgeops`  

---

## 1. Executive Summary

Gate G11 successfully delivers end-to-end distributed tracing across the ForgeOps platform using Grafana Tempo and OpenTelemetry, natively integrated with the existing G09 (Prometheus/Grafana) and G10 (Loki/Alloy) observability architecture.

All four implementation and promotion PRs were merged cleanly via standard merge commits after passing required GitHub Actions CI gates, container vulnerability scans (Trivy 0 CRITICAL / 0 HIGH), and secret scanning. The updated ForgeTasks API (Spring Boot 4.1.2 / Java 21) was published to GitHub Container Registry as an immutable, runnable image manifest, promoted through GitOps rehearsal configuration, rolled out smoothly with zero downtime, and verified against all 18 live acceptance criteria.

---

## 2. PR Traceability & Merge Commit Record

| PR # | Branch | Purpose | Merge Commit SHA | CI Status |
|:---|:---|:---|:---|:---|
| **#40** | `feat/g11-opentelemetry-tracing` | Spring Boot 4.1.2 OpenTelemetry OTLP tracing, W3C propagation, and test suite | `4f2ec0dc2cf7b42ff6d63428ecbf17992cb91b93` | Passed |
| **#41** | `feat/g11-tempo-alloy-tracing` | Grafana Tempo 1.24.4 monolithic chart, Alloy OTLP pipeline, Grafana `tracesToLogsV2` datasource | `1d62b988f5a6f874465fe9efab836bfa75ea8e05` | Passed |
| **#42** | `fix/g11-publish-workflow-syntax` | Hardening and YAML syntax normalization in `.github/workflows/publish.yml` | `ed0521e21beabc44ca7e2163f2d8f5b21ce7256e` | Passed |
| **#43** | `chore/g11-promote-rehearsal-api-image` | GitOps rehearsal image promotion in `values-rehearsal.yaml` to `1.0.0-g11` | `4aef7800d3254d5c196333e5673a45a712f8c735` | Passed |

---

## 3. Container Image Provenance & Verification

The ForgeTasks API container image was compiled and verified through the publication workflow [Run ID 40627166086](https://github.com/TM-threemavithana/ForgeOps/actions/runs/40627166086) with manual release approval:

- **Canonical Repository:** `ghcr.io/tm-threemavithana/forgetasks-api`
- **Release SemVer Tag:** `1.0.0-g11`
- **Source Revision SHA:** `ed0521e21beabc44ca7e2163f2d8f5b21ce7256e`
- **Authoritative Primary Digest:** `sha256:2d685ae46db121dfa4ccfbfc51859159dbc553b72897adf2c829d90357105bcf`
- **Image Manifest Media Type:** `application/vnd.docker.distribution.manifest.v2+json`
- **Layer Count:** 8 layers (non-empty root filesystem, total uncompressed size 131MB)
- **Container Entrypoint:** `java -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -Djava.security.egd=file:/dev/./urandom -jar /app/forgetasks-api.jar`
- **User Execution:** Non-root UID `10001:10001` (`appuser:appgroup`)
- **Trivy Vulnerability Scan:** 0 CRITICAL / 0 HIGH vulnerabilities detected.

---

## 4. Protected Infrastructure & PVC Continuity

All pre-existing storage volumes and namespaces remained strictly isolated and unharmed throughout deployment and testing.

| PVC Name | Namespace | Target Workload | Status | Capacity | Documented Baseline UID | Live Verified UID |
|:---|:---|:---|:---|:---|:---|:---|
| `postgres-storage-forgetasks-db-0` | `forgeops-dev` | G06 Dev PostgreSQL | `Bound` | 1Gi | `84853fb3-4d13-43a9-bc62-973c3be3c90c` | `84853fb3-4d13-43a9-bc62-973c3be3c90c` |
| `postgres-storage-forgetasks-rehearsal-db-0` | `forgeops-gitops-rehearsal` | G08 Rehearsal PostgreSQL | `Bound` | 1Gi | `b5ea8ec9-47e8-4979-afdb-621f2e3c63b8` | `b5ea8ec9-47e8-4979-afdb-621f2e3c63b8` |
| `prometheus-g09-monitoring-...-0` | `forgeops-observability` | G09 Prometheus TSDB | `Bound` | 2Gi | `cd64e090-2c69-49b3-a389-de5841ce06d6` | `cd64e090-2c69-49b3-a389-de5841ce06d6` |
| `storage-loki-0` | `forgeops-observability` | G10 Loki TSDB | `Bound` | 2Gi | `23468366-7394-4f2d-be1f-2a640d6f12c5` | `23468366-7394-4f2d-be1f-2a640d6f12c5` |
| `storage-tempo-0` | `forgeops-observability` | **G11 Tempo Tracing** | `Bound` | **2Gi** | *New in G11* | `092b6655-6617-467c-b546-69e201a0ba8a` |

- **Rehearsal Auto-Sync Guard:** Confirmed `syncPolicy.automated.enabled: false` on `Application/forgetasks-rehearsal`.
- **Database Consistency:** Database account count before testing: `2`; count after testing: `2` (0 mutations).

---

## 5. Argo CD Application Status

All 6 GitOps applications in the Argo CD control plane are fully synchronized and healthy:

| Application | Project | Sync Status | Health Status | Auto-Sync Policy |
|:---|:---|:---|:---|:---|
| `forgetasks-rehearsal` | `forgeops-rehearsal-project` | `Synced` | `Healthy` | **Disabled** (`enabled: false`) |
| `g09-monitoring` | `forgeops-observability-project` | `Synced` | `Healthy` | Manual |
| `g10-alloy` | `forgeops-logging-project` | `Synced` | `Healthy` | Manual |
| `g10-grafana-datasource` | `forgeops-logging-project` | `Synced` | `Healthy` | Manual |
| `g10-loki` | `forgeops-logging-project` | `Synced` | `Healthy` | Manual |
| `g11-tempo` | `forgeops-logging-project` | `Synced` | `Healthy` | Manual |

---

## 6. Live Tracing Acceptance Verification Summary

The complete 18-step acceptance verification suite (`scripts/cluster/test-g11-observability.sh`) executed cleanly with 100% pass rate:

1. **PVC UIDs:** All 4 protected PVC UIDs matched documented baselines identically.
2. **Pod Health:** `loki-0`, `tempo-0`, `alloy-84547b4558-qdcgl`, `forgetasks-rehearsal-api-68fb7f76c7-4fk58`, and `forgetasks-rehearsal-db-0` pods all reported `Ready`.
3. **Host Port-Forwards:** Localhost port-forwards established cleanly on ports `13100` (Loki), `13200` (Tempo), `12345` (Alloy), `13000` (Grafana), `19090` (Prometheus), and `18080` (Rehearsal API).
4. **Tempo Readiness & Storage:** Tempo `/ready` returned HTTP 200 OK (`ready`), and PVC `storage-tempo-0` was verified at `2Gi`.
5. **Alloy OTLP Pipeline:** Alloy `/-/healthy` returned HTTP 200 OK, and configuration confirmed active `otelcol.receiver.otlp` and `otelcol.exporter.otlp` components.
6. **Scoped RBAC:** Alloy ServiceAccount positively authorized to read pods in `forgeops-gitops-rehearsal`, negatively denied in `forgeops-dev` and denied secrets. Tempo ServiceAccount verified with zero cluster privileges.
7. **Baseline DB Check:** Recorded 2 existing accounts in rehearsal PostgreSQL.
8. **HTTP Probe & W3C Context:** Deterministic HTTP POST to `/api/v1/accounts` with `X-Request-ID: req-g11-probe-1793160661-26427` and W3C `traceparent: 00-e060b7afe2a2d682ac61bd4b00256ddb-0e61fe07afaa58d0-01` returned HTTP 400 Bad Request with matching `correlationId` in response headers and ProblemDetail JSON body.
9. **Zero DB Mutation:** Post-probe database account count remained identical at 2.
10. **Loki Correlation:** Queried Loki for `{app="rehearsal-api"} |= "req-g11-probe-1793160661-26427"`; verified top-level `traceId: e060b7afe2a2d682ac61bd4b00256ddb` and `spanId` emitted in ECS JSON format.
11. **Tempo Trace Retrieval:** Queried Tempo `/api/traces/e060b7afe2a2d682ac61bd4b00256ddb`; retrieved full trace batch containing `SPAN_KIND_SERVER` and child security observation spans.
12. **Sensitive Data Exclusion:** Verified zero raw passwords (`SuperSecretProbePassword999!`), authorization credentials, or bearer tokens leaked in span attributes, event names, or resource metadata.
13. **Low-Cardinality Indexing:** Confirmed Loki labels remain low-cardinality (`app`, `container`, `namespace`); neither `traceId` nor `spanId` were promoted to Loki index labels.
14. **Grafana Tempo Datasource:** Verified provisioned Tempo datasource with `customQuery: true`, `datasourceUid: "loki"`, and trace-to-logs query `{app="rehearsal-api"} |= "${__trace.traceId}"`.
14b. **Trace-to-Logs Live Query:** Executed the exact Grafana LogQL query against Loki with the live trace ID; returned matching ECS log event.
15. **Prometheus Continuity:** Queried Prometheus scrape targets; confirmed 100% of targets remain `UP` and healthy.
16. **Negative Log Isolation:** Verified exactly 0 logs from `forgeops-dev` exist in Loki.
17. **Retention Configuration:** Verified declarative 24h block retention (`block_retention: 24h`) in Tempo configuration.
18. **Suite Pass:** Full suite completed with exit status 0 and clean background process teardown.

---

## 7. Artifacts & Evidence Files

- `docs/evidence/G11/acceptance-verification.log`: Complete stdout/stderr transcript of the 18-step verification execution.
- `docs/evidence/G11/pvc-continuity.txt`: Definitive cluster PVC table with UIDs, volume names, and statuses.
- `docs/evidence/G11/cluster-inventory.txt`: Full cluster inventory across Argo CD, pods, and services.
- `docs/evidence/G11/trace-sample.json`: Exported trace sample retrieved from Tempo internal HTTP API.
- `docs/evidence/G11/G11-acceptance-report.md`: This comprehensive acceptance report.

---

## 8. Remaining Limitations & Operating Notes

1. **Retention Duration Verification:** Declarative retention is set to 24h (`block_retention: 24h`). Physical trace pruning is verified by configuration and logs; empirical 24h elapsed expiry is not claimed as the cluster has run for less than 24h.
2. **Reverse Log-to-Trace Navigation:** Forward navigation (Tempo trace-to-logs via LogQL) is verified and functional. Reverse log-to-trace derived fields are intentionally reserved for a future observability refinement gate.
3. **Kind Network IPv6 Mitigation:** The local Kind node uses `net.ipv6.conf.all.disable_ipv6=1` to guarantee fast IPv4 fallback when connecting to external registries (`ghcr.io`, `pkg-containers.githubusercontent.com`).

---

**Conclusion:** ForgeOps Gate G11 is fully completed, verified, and ready for production promotion sign-off.
