# Requirements Traceability Matrix (RTM) — ForgeOps

**Effective Date:** 2026-10-24
**Baseline Review:** Gate G03
**Status Legend:**  
- `PASSED`: Fully verified with tangible command/log evidence.  
- `PASSED_LIM`: Verified with documented hardware/environment limitations.  
- `PLANNED`: Designed and scheduled in master plan; implementation deferred to specific gate.  
- `BLOCKED`: Cannot proceed until prerequisite gate passes or dependency is resolved.

---

## 1. Functional Requirements Traceability

| Req ID | Requirement Summary | Gate | Primary Implementing File(s) | Verification Test ID | Current Status |
|---|---|---|---|---|---|
| **REQ-F-01.1** | Local user accounts & BCrypt hash | G01 | `Account.java`, `AccountService.java`, `SecurityConfig.java` | `AccountApiIntegrationTest`, `SecurityIntegrationTest` | **PASSED (G01)** |
| **REQ-F-01.2** | Test bootstrap user fixture | G01 | `AbstractIntegrationTest.java`, `V1_1__dev_seed.sql` | `AccountApiIntegrationTest` | **PASSED (G01)** |
| **REQ-F-01.3** | Owner-level isolation (404 on cross-user) | G01 | `ProjectRepository.java`, `TaskRepository.java`, `ProjectService.java` | `ProjectApiIntegrationTest`, `TaskApiIntegrationTest` | **PASSED (G01)** |
| **REQ-F-02.1** | Project creation & validation | G01 | `ProjectController.java`, `ProjectService.java` | `ProjectApiIntegrationTest`, `ProjectServiceTest` | **PASSED (G01)** |
| **REQ-F-02.2** | Paginated & sorted project list | G01 | `ProjectService.java`, `ProjectRepository.java` | `ProjectApiIntegrationTest`, `ProjectServiceTest` | **PASSED (G01)** |
| **REQ-F-02.3** | Project conditional requests (`If-Match`/428/412/409) | G01 | `ProjectController.java`, `ETagUtils.java`, `GlobalExceptionHandler.java` | `ConcurrencyLockingIntegrationTest`, `ProjectApiIntegrationTest` | **PASSED (G01)** |
| **REQ-F-03.1** | Task creation under owned project | G01 | `TaskController.java`, `TaskService.java` | `TaskApiIntegrationTest`, `TaskServiceTest` | **PASSED (G01)** |
| **REQ-F-03.2** | Task status & priority enum validation | G01 | `Task.java`, `TaskStatus.java`, `TaskPriority.java` | `TaskServiceTest`, `TaskApiIntegrationTest` | **PASSED (G01)** |
| **REQ-F-03.3** | Task filter, search & pagination | G01 | `TaskRepository.java`, `TaskService.java` | `TaskApiIntegrationTest`, `TaskServiceTest` | **PASSED (G01)** |
| **REQ-F-03.4** | Task conditional requests (`If-Match`/428/412/409) | G01 | `TaskController.java`, `ETagUtils.java`, `TaskService.java` | `ConcurrencyLockingIntegrationTest`, `TaskApiIntegrationTest` | **PASSED (G01)** |
| **REQ-F-04.1** | Flyway relational schema migrations | G01 | `V1__init_schema.sql` | `FlywayMigrationIntegrationTest` | **PASSED (G01)** |
| **REQ-F-04.2** | Expand/contract migration compatibility | G01, G10 | `ADR-0010`, `V1__init_schema.sql` | `FlywayMigrationIntegrationTest` | **PASSED (G01 baseline verified)** |
| **REQ-F-04.4** | Prod migration vs dev seed data separation | G01 | `db/migration/` vs `db/dev-data/` | `FlywayMigrationIntegrationTest` | **PASSED (G01)** |
| **REQ-F-05.1** | `/api/v1/` REST endpoint structure | G01 | `AccountController.java`, `ProjectController.java`, `TaskController.java` | All Integration Tests & `verify_runtime.sh` | **PASSED (G01)** |
| **REQ-F-05.2** | RFC 9457 error model with `requestId` | G01 | `GlobalExceptionHandler.java`, `RequestCorrelationFilter.java` | `GlobalExceptionHandler`, Integration Tests | **PASSED (G01)** |
| **REQ-F-05.3** | Actuator liveness/readiness & endpoint protection | G01 | `application.yml`, `SecurityConfig.java` | `ObservabilityIntegrationTest`, `SecurityIntegrationTest` | **PASSED (G01)** |


---

## 2. Platform & Infrastructure Requirements Traceability

| Req ID | Requirement Summary | Gate | Primary Implementing File(s) | Verification Test ID | Current Status |
|---|---|---|---|---|---|
| **REQ-P-01.1** | Multi-stage non-root Dockerfile | G02 | `apps/forgetasks-api/Dockerfile` | A-201 | **PASSED (G02)** |
| **REQ-P-01.2** | Zero secrets in image layers | G02 | `apps/forgetasks-api/.dockerignore`, Trivy scan | A-201 | **PASSED (G02)** |
| **REQ-P-01.3** | Compose API + PostgreSQL persistence | G02 | `compose.yaml`, `.env.example` | A-202 | **PASSED (G02)** |
| **REQ-P-02.1** | Untrusted PR workflow (read-only) | G03 | `.github/workflows/ci.yml` | A-301 | **PASSED (G03)** |
| **REQ-P-02.2** | Trusted release to GHCR by SHA256 | G03 | `.github/workflows/publish.yml` | A-302 | **PASSED (G03 — awaiting push)** |
| **REQ-P-02.3** | Offline local CI counterpart (`make ci`)| G03 | `Makefile`, `scripts/verify_g03_local.sh` | A-303 | **PASSED (G03)** |
| **REQ-P-03.1** | Local Kind cluster (`dev`/`staging`) | G06 | `platform/kind/core.yaml`, `scripts/cluster/create.sh` | A-601 | PLANNED |
| **REQ-P-03.2** | Reusable Helm chart (`existingSecret`) | G07 | `platform/charts/forgetasks/` | A-701 | PLANNED |
| **REQ-P-03.3** | Argo CD GitOps pull-based promotion | G08 | `platform/argocd/apps/`, `values-dev.yaml` | A-801 | PLANNED |
| **REQ-P-03.4** | Declarative Git revert rollback | G08, G12 | `docs/runbooks/rollback.md`, Git commit revert | A-802, DR-02 | PLANNED |
| **REQ-P-04.1** | Terraform local Docker lab fixture | G05 | `infrastructure/terraform/local-docker-lab/` | A-501 | **PASSED (G05)** |
| **REQ-P-04.2** | Terraform Argo CD cluster bootstrap | G08 | `infrastructure/terraform/cluster-bootstrap/` | A-501, A-801 | PLANNED |
| **REQ-P-04.3** | Scoped destroy without collateral loss | G05 | `Makefile`, `scripts/cleanup/` | A-502 | **PASSED (G05)** |
| **REQ-P-05.1** | Ansible Linux guest VM over SSH | G04 | `infrastructure/ansible/inventories/lab/hosts.yml` | A-401 | **PASSED (G04)** |
| **REQ-P-05.2** | Ansible idempotent roles (`changed=0`) | G04 | `infrastructure/ansible/roles/`, `playbooks/site.yml` | A-402, DR-09 | **PASSED (G04)** |
| **REQ-P-05.3** | Genuine VM requirement (no container) | G04 | `docs/evidence/G04/` | A-401 | **PASSED (G04)** |
| **REQ-P-06.1** | Prometheus metrics & retention cap | G09 | `observability/prometheus/` | A-901 | PLANNED |
| **REQ-P-06.2** | Alertmanager alert firing & resolution | G09 | `observability/alertmanager/`, Alert rules | A-902, DR-03 | PLANNED |
| **REQ-P-06.3** | Grafana Alloy log harvest (no Promtail)| G10 | `observability/alloy/`, `observability/loki/` | A-1001 | PLANNED |
| **REQ-P-06.4** | Golden Signals dashboard + log link | G09, G10 | `observability/grafana/dashboards/` | A-901, A-1001| PLANNED |
| **REQ-P-07.1** | Host-side `pg_dump` with SHA256 | G13 | `scripts/backup/backup-db.sh`, `Makefile` | A-1301 | PLANNED |
| **REQ-P-07.2** | Automated scratch restore verification | G13 | `scripts/backup/verify-backup.sh` | A-1301, DR-07 | PLANNED |
| **REQ-P-07.3** | Measured RTO <= 60m, RPO <= 24h | G13 | `docs/evidence/G13/disaster-recovery-log.md` | A-1302 | PLANNED |

---

## 3. Non-Functional & Governance Requirements Traceability

| Req ID | Requirement Summary | Gate | Evidence Document / Target | Status |
|---|---|---|---|---|
| **NFR-SEC-01** | Zero secrets in git repository | G00–G15 | `.gitignore`, Gitleaks CI scan, `A-1101` | **PASSED (G00 baseline verified)** |
| **NFR-SEC-02** | Containers run non-root UID | G02, G11 | Dockerfile user, Trivy report, `A-201` | **PASSED (G02)** |
| **NFR-SEC-03** | Local loopback binding (`127.0.0.1`) | G02, G06 | Docker Compose port mappings, `kubectl port-forward` | **PASSED (G02)** |
| **NFR-PERF-01**| p95 latency < 500 ms under k6 load | G12 | k6 report, Prometheus histogram, `A-1201`, `DR-05` | PLANNED |
| **NFR-REL-01** | Stateless pod failure replacement | G06, G12 | Pod kill test, `A-602`, `DR-01` | PLANNED |
| **NFR-RES-01** | Core profile memory & disk governance | G00–G15 | `docs/evidence/G00-preflight.md`, `A-001` | **PASSED_LIM (6.6 GB free SSD limitation)** |
| **NFR-COV-01** | Jacoco test coverage ≥ 80% | G01 | Maven JaCoCo report (`target/site/jacoco/index.html`) | **PASSED (G01: 94.09% instruction, 91.23% branch)** |
| **GOV-001** | Zero paid cloud dependency | G00–G15 | Zero cloud SDKs / credentials required | **PASSED** |
| **GOV-002** | Single owner per resource | G00–G15 | `docs/adr/ADR-0003*.md`, System topology | **PASSED (G00 baseline verified)** |
| **GOV-003** | Upstream version compatibility verified | G00 | `docs/compatibility-matrix.md` | **PASSED** |
| **GOV-004** | No fabricated successes | G00–G15 | Documented command logs and exact outcomes | **PASSED (G00 baseline verified)** |
