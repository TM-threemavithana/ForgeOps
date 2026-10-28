# ForgeOps Requirements Traceability Matrix (Gates G00–G14)

| Metadata | Details |
|:---|:---|
| **Auditor** | Principal DevOps Engineer, Senior SRE & Platform Security Architect |
| **Project** | ForgeOps — Self-Hosted DevOps & Platform Engineering Lab |
| **Repository** | `TM-threemavithana/ForgeOps` |
| **Target Context** | Local Workstation (Linux/WSL2 Ubuntu 24.04 LTS, Docker Desktop, Kind v0.27.0) |
| **Audit Date** | 2026-10-28 |
| **Audit Status** | **COMPLETE & VERIFIED** |

---

## 1. Classification & Status Legend

- **`PASSED`**: Requirement fully implemented, tested against automated verification, backed by authentic persistent evidence, and operating within defined specifications.
- **`PASSED_WITH_LIMITATIONS`**: Requirement successfully implemented and functional, but operating under documented architectural or environment constraints (e.g., local CNI limitations, synthetic lab boundaries).
- **`DEFERRED`**: Capability intentionally excluded or rescheduled to protect host capacity or avoid commercial cloud requirements.
- **`FAILED`**: Requirement failed verification, broke platform invariants, or remains unresolved.

---

## 2. Requirements Traceability Ledger

### G00 — Preflight, Architecture Baseline & Hardware Feasibility

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G00-01** | Verify Linux/WSL2 virtualization, Docker Engine availability, and memory/disk headroom. | `scripts/dev/preflight.sh`, `Makefile` | `make doctor`, OS kernel and resource inspection | [`docs/evidence/G00-preflight.md`](../evidence/G00-preflight.md) | **PASSED** | Workstation RAM contention if multiple heavy profiles run simultaneously. |
| **REQ-G00-02** | Establish execution profiles (Core, Extended, Capstone) and strict zero paid cloud boundaries. | `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` | Architecture review & profile mapping | [`docs/evidence/G00-preflight.md`](../evidence/G00-preflight.md) | **PASSED** | High-concurrency operations require sequential execution on 8–16 GB machines. |

---

### G01 — ForgeTasks Backend API & Database Schema

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G01-01** | Multi-tenant REST API with hierarchical Accounts, Projects, and Tasks backed by PostgreSQL. | `apps/forgetasks-api/src/main/java/dev/forgeops/api/` | Maven unit & integration tests (`./mvnw verify`), Testcontainers | [`docs/evidence/G01/acceptance.md`](../evidence/G01/acceptance.md) | **PASSED** | Single backend application; no microservice distributed transactions. |
| **REQ-G01-02** | Tenant data isolation returning `HTTP 404` on foreign tenant resource access (anti-enumeration). | `ProjectRepository.java`, `TaskRepository.java`, `TaskService.java` | Integration tests with multiple tenant accounts | [`docs/evidence/G01/acceptance.md`](../evidence/G01/acceptance.md) | **PASSED** | Application-level isolation; shared physical PostgreSQL database schema. |
| **REQ-G01-03** | Optimistic concurrency & lost update prevention (RFC 7232/9110 ETag/If-Match, 412/428 errors). | `TaskController.java`, `TaskVersionMismatchException.java` | Concurrent mutating HTTP request tests | [`docs/evidence/G01/acceptance.md`](../evidence/G01/acceptance.md) | **PASSED** | Requires clients to properly capture and echo ETag headers on updates. |
| **REQ-G01-04** | Flyway declarative database migrations and automatic schema versioning. | `apps/forgetasks-api/src/main/resources/db/migration/` | Migration execution on startup, checksum verification | [`docs/evidence/G01/acceptance.md`](../evidence/G01/acceptance.md) | **PASSED** | Destructive column alters require explicit expansion/contraction migrations. |
| **REQ-G01-05** | Standardized error details (RFC 9457 `ProblemDetail`) and `X-Request-ID` correlation logging. | `GlobalExceptionHandler.java`, `RequestCorrelationFilter.java` | MockMvc assertion of ProblemDetail JSON responses | [`docs/evidence/G01/acceptance.md`](../evidence/G01/acceptance.md) | **PASSED** | None. Conforms strictly to IETF standards. |

---

### G02 — Multi-Stage Containerization & Local Docker Stack

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G02-01** | Hardened multi-stage Dockerfile running as non-root UID 10001 on minimal JRE runtime. | `apps/forgetasks-api/Dockerfile` | `docker inspect`, `whoami` execution check | [`docs/evidence/G02/acceptance.md`](../evidence/G02/acceptance.md) | **PASSED** | Alpine musl libc runtime constraints; compatibility verified for Java 21. |
| **REQ-G02-02** | Docker Compose local development environment with isolated loopback exposure (`127.0.0.1:18080`). | `deploy/docker-compose.yml`, `.env.example` | `docker compose up -d`, port binding inspection | [`docs/evidence/G02/acceptance.md`](../evidence/G02/acceptance.md) | **PASSED** | Port 18080 must not conflict with host development services. |
| **REQ-G02-03** | Out-of-band secret injection using Docker Compose secrets and Spring Boot configtree. | `deploy/docker-compose.yml`, `secrets/` | Application boots without environment plaintext passwords | [`docs/evidence/G02/acceptance.md`](../evidence/G02/acceptance.md) | **PASSED** | Local secrets directory must remain in `.gitignore`. |
| **REQ-G02-04** | Health probes (`/actuator/health/liveness`, `/actuator/health/readiness`) and Prometheus scrape endpoint. | `application.yml`, Spring Boot Actuator | `curl -f` against health endpoints | [`docs/evidence/G02/acceptance.md`](../evidence/G02/acceptance.md) | **PASSED** | Liveness probe decoupled from DB; readiness probe validates DB connection. |

---

### G03 — GitHub Actions CI/CD, Supply Chain Security & GHCR

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G03-01** | Automated build, test, and JaCoCo code coverage enforcement in GitHub Actions CI. | `.github/workflows/ci.yml` | GitHub Actions runner execution | [`docs/evidence/G03/acceptance.md`](../evidence/G03/acceptance.md) | **PASSED** | Runner dependent on GitHub Actions cloud availability. |
| **REQ-G03-02** | Secret leak prevention scanning full git history via Gitleaks. | `.github/workflows/ci.yml`, `.gitleaks.toml` | CI Gitleaks job, canary leak test assertions | [`docs/evidence/G03/acceptance.md`](../evidence/G03/acceptance.md) | **PASSED** | Requires ongoing maintenance of `.gitleaksignore` for false positives. |
| **REQ-G03-03** | Vulnerability scanning via Trivy enforcing zero CRITICAL/HIGH CVEs on built images. | `.github/workflows/ci.yml`, `.github/workflows/publish.yml` | Trivy security scanner step with exit code 1 | [`docs/evidence/G03/acceptance.md`](../evidence/G03/acceptance.md) | **PASSED** | Zero-day CVE disclosures in upstream base images require periodic updates. |
| **REQ-G03-04** | Software Bill of Materials (SBOM) generation using CycloneDX format. | `.github/workflows/publish.yml` | CycloneDX SBOM artifact generation and upload | [`docs/evidence/G03/acceptance.md`](../evidence/G03/acceptance.md) | **PASSED** | None. Standard machine-readable dependency inventory. |
| **REQ-G03-05** | SLSA Build Provenance attestation via Sigstore to GitHub Container Registry (GHCR). | `.github/workflows/publish.yml` | `actions/attest-build-provenance@v2` execution | [`docs/evidence/G03/acceptance.md`](../evidence/G03/acceptance.md) | **PASSED** | Attestation OCI bundles must not be confused with runnable image manifests. |
| **REQ-G03-06** | Authoritative GHCR publishing with master-branch ancestry and CI status gate verification. | `.github/workflows/publish.yml`, `test_publish_hardening.py` | Automated test suite with 70 assertions | [`docs/evidence/G03/publish-hardening.md`](../evidence/G03/publish-hardening.md) | **PASSED** | Requires GitHub Environment protection rules for production promotion. |

---

### G04 — Ansible Linux Host Configuration Management

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G04-01** | Control Ubuntu Linux guest over SSH with Ansible playbooks, inventories, and roles. | `ansible/playbooks/`, `ansible/roles/` | SSH connection from WSL to guest, `ansible-playbook` | [`docs/evidence/G04/readiness.md`](../evidence/G04/readiness.md) | **PASSED** | Requires local VM hypervisor configuration (VirtualBox/Hyper-V). |
| **REQ-G04-02** | Idempotent playbook execution and check-mode (`--check`) verification. | `ansible/roles/forgeops_common/` | Zero changes (`changed=0`) on secondary playbook execution | [`docs/evidence/G04/readiness.md`](../evidence/G04/readiness.md) | **PASSED** | Host network firewall settings must permit local SSH loopback/host-only traffic. |

---

### G05 — Terraform Local Docker Infrastructure

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G05-01** | Provision local container infrastructure using Terraform Docker provider. | `terraform/environments/local/`, `terraform/modules/` | `terraform plan`, `terraform apply` | [`docs/evidence/G05/readiness.md`](../evidence/G05/readiness.md) | **PASSED** | Local state file; cloud remote backends excluded by design. |
| **REQ-G05-02** | State protection, plan validation, and automated drift detection. | `terraform/environments/local/` | Intentional container drift injection and `terraform plan` | [`docs/evidence/G05/readiness.md`](../evidence/G05/readiness.md) | **PASSED** | Docker provider lifecycle tied strictly to local Docker daemon. |

---

### G06 — Local Kind Kubernetes Cluster & Workloads

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G06-01** | Provision single-node Kind Kubernetes cluster with persistent local path storage. | `platform/kind/cluster-config.yaml`, `scripts/cluster/create-cluster.sh` | Cluster bootstrap execution, `kubectl cluster-info` | [`docs/evidence/G06/readiness.md`](../evidence/G06/readiness.md) | **PASSED** | Single-node cluster; node-level high availability is not possible. |
| **REQ-G06-02** | Deploy ForgeTasks API and PostgreSQL into isolated `forgeops-dev` namespace. | `platform/k8s/dev/` | Vanilla manifest deployment, pod readiness checks | [`docs/evidence/G06/readiness.md`](../evidence/G06/readiness.md) | **PASSED** | Manual YAML deployments superseded by Helm and GitOps in later gates. |
| **REQ-G06-03** | In-Cluster NetworkPolicy packet filtering and pod traffic restriction. | `platform/k8s/dev/networkpolicy.yaml` | Manifest rendering check | **PASSED_WITH_LIMITATIONS** | **Documented limitation:** Default Kind `kindnet` CNI lacks eBPF/iptables policy filtering. Policies exist as specifications but are not actively filtered at packet level. |

---

### G07 — Helm Application Chart Packaging & Parameterization

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G07-01** | Reusable, parameterized Helm chart for ForgeTasks API and PostgreSQL database. | `platform/charts/forgetasks/` | `helm lint`, `helm template` dry-run validation | [`docs/evidence/G07/readiness.md`](../evidence/G07/readiness.md) | **PASSED** | None. Standard Helm v3 packaging conventions. |
| **REQ-G07-02** | Environment-specific values overrides (`values-dev.yaml`, `values-rehearsal.yaml`). | `platform/charts/forgetasks/values-*.yaml` | Dry-run template comparison across profiles | [`docs/evidence/G07/readiness.md`](../evidence/G07/readiness.md) | **PASSED** | Values files must maintain parity as new configuration keys are added. |

---

### G08 — Platform Bootstrap & Argo CD GitOps Delivery

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G08-01** | Argo CD GitOps controller bootstrap and Application manifest declaration. | `platform/gitops/argocd/`, `platform/gitops/apps/` | Argo CD pod health, CRD creation, UI access | [`docs/evidence/G08/readiness.md`](../evidence/G08/readiness.md) | **PASSED** | Argo CD runs in local cluster; UI bound to loopback `127.0.0.1:18081`. |
| **REQ-G08-02** | Safe GitOps deployment workflow using manual sync (`automated.enabled: false`). | `platform/gitops/apps/forgetasks-rehearsal.yaml` | Verification of disabled auto-sync setting | [`docs/evidence/G08/readiness.md`](../evidence/G08/readiness.md) | **PASSED** | Requires explicit engineer sync trigger via UI or CLI to deploy changes. |
| **REQ-G08-03** | Immutable deployment references via container image SHA-256 digests (`@sha256:...`). | `platform/charts/forgetasks/values-rehearsal.yaml` | Manifest inspection, zero mutable tag updates | [`docs/evidence/G08/readiness.md`](../evidence/G08/readiness.md) | **PASSED** | Promoted digests must be validated as runnable OCI images (see G10 incident). |

---

### G09 — Prometheus Metrics & Alertmanager Alerting

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G09-01** | Prometheus metric scraping covering JVM, HTTP request rates, and HikariCP connection pools. | `platform/monitoring/prometheus/` | PromQL query execution (`http_server_requests_seconds_count`) | [`docs/evidence/G09/README.md`](../evidence/G09/README.md) | **PASSED** | Prometheus persistent volume retention configured to 15 days (bounded disk). |
| **REQ-G09-02** | Alertmanager notification rules for high error rates, database disconnection, and pod restarts. | `platform/monitoring/alertmanager/` | Synthetic alert firing and resolution validation | [`docs/evidence/G09/README.md`](../evidence/G09/README.md) | **PASSED** | Email/Slack receivers stubbed to loopback webhook receiver in local lab. |

---

### G10 — Centralized Logging with Loki & Grafana Alloy

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G10-01** | Centralized pod log harvesting via Grafana Alloy agent streaming to Grafana Loki. | `platform/logging/alloy/`, `platform/logging/loki/` | LogQL query execution in Grafana Explore | [`docs/evidence/G10/G10-acceptance-report.md`](../evidence/G10/G10-acceptance-report.md) | **PASSED** | Local filesystem chunk storage; WAL cleanup required if disk headroom shrinks. |
| **REQ-G10-02** | Structured ECS JSON log formatting with `X-Request-ID` correlation propagation. | `logback-spring.xml`, `RequestCorrelationFilter.java` | LogQL correlation queries filtering by request ID | [`docs/evidence/G10/G10-acceptance-report.md`](../evidence/G10/G10-acceptance-report.md) | **PASSED** | Plaintext log files restricted to container stdout (zero secret logging). |
| **REQ-G10-03** | Incident root-cause analysis and GitOps recovery for OCI attestation bundle digest mismatch. | PR #32, PR #33 | Forensics on GHCR mediaType, forward-fix PR merge | [`docs/evidence/G10/G10-B-incident-and-recovery-report.md`](../evidence/G10/G10-B-incident-and-recovery-report.md) | **PASSED** | Documented critical learning on OCI artifact types vs runnable images. |

---

### G11 — Distributed Tracing with Grafana Tempo & OpenTelemetry

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G11-01** | OpenTelemetry Java auto-instrumentation and W3C `traceparent` context propagation. | `apps/forgetasks-api/Dockerfile`, `application.yml` | HTTP request headers with `traceparent` inspection | [`docs/evidence/G11/G11-acceptance-report.md`](../evidence/G11/G11-acceptance-report.md) | **PASSED** | OTel Java agent introduces ~50 MB JVM heap overhead (profile-budgeted). |
| **REQ-G11-02** | Distributed trace ingestion via Grafana Tempo backend and `tracesToLogsV2` navigation bridge. | `platform/tracing/tempo/`, `platform/monitoring/grafana/` | Direct trace lookup by Trace ID, trace-to-log clickthrough | [`docs/evidence/G11/G11-acceptance-report.md`](../evidence/G11/G11-acceptance-report.md) | **PASSED** | **Gate Scope Note:** Implemented in G11 to complete the observability triad ahead of G12 SRE load testing. |

---

### G12 — SRE Reliability Engineering, Load Testing & Chaos Injection

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G12-01** | Progressive k6 load testing scenarios with arrival-rate limits (capped at 20 req/s, 2,275 requests). | `tests/load/scenarios/`, `tests/load/run-k6.sh` | Execution of 5 progressive k6 test scenarios | [`docs/evidence/G12/G12-acceptance-report.md`](../evidence/G12/G12-acceptance-report.md) | **PASSED_WITH_LIMITATIONS** | **Documented limitation:** Tested through bounded single-backend port-forward (`127.0.0.1:8082`). True multi-replica load balancing requires Ingress/Service routing. |
| **REQ-G12-02** | Controlled resilience failure experiments (Pod kill, CPU stress, DB drop, bad image, latency). | `tests/resilience/` | 5 automated failure injection scripts with TTD/TTR tracking | [`docs/evidence/G12/G12-acceptance-report.md`](../evidence/G12/G12-acceptance-report.md) | **PASSED** | Experiments executed strictly inside isolated disposable namespace `forgeops-sre-lab`. |
| **REQ-G12-03** | SLI/SLO definition, error budget tracking, and operational incident response runbooks. | `docs/sre-sli-slo-spec.md`, `docs/runbooks/` | Four detailed incident runbooks, simulated incident drills | [`docs/evidence/G12/G12-acceptance-report.md`](../evidence/G12/G12-acceptance-report.md) | **PASSED** | Simulated incident drills; no production customer on-call paging. |

---

### G13 — PostgreSQL Backup, Recovery Automation & Disaster Recovery Rehearsal

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G13-01** | Declarative PostgreSQL backup automation using `pg_dump` custom format with SHA-256 verification. | `scripts/cluster/dr/backup-db.sh` | Backup archive creation, checksum generation | [`docs/evidence/G13/G13-acceptance-report.md`](../evidence/G13/G13-acceptance-report.md) | **PASSED** | Measured backup time: 273 ms (lightweight synthetic dataset). |
| **REQ-G13-02** | Strict restoration automation (`restore-db.sh`) targeting empty disposable instances. | `scripts/cluster/dr/restore-db.sh` | Fresh instance restore execution, `pg_restore --exit-on-error` | [`docs/evidence/G13/G13-acceptance-report.md`](../evidence/G13/G13-acceptance-report.md) | **PASSED** | Measured restore command duration: 252 ms. Full end-to-end API recovery RTO: 89.29 seconds. |
| **REQ-G13-03** | End-to-end disaster recovery rehearsal with multi-tenant authenticated smoke tests. | `scripts/cluster/dr/rehearse-dr.sh` | Full automated rehearsal drill, teardown, PVC audit | [`docs/evidence/G13/G13-acceptance-report.md`](../evidence/G13/G13-acceptance-report.md) | **PASSED_WITH_LIMITATIONS** | **Documented limitation:** Drill conducted on synthetic disposable database (`forgeops-dr-lab`); not a test of bare-metal cluster reconstruction or terabyte-scale recovery. 12-second backup age is test interval, not guaranteed operational RPO. |

---

### G14 — Policy-as-Code & Encrypted Secrets Management

| Req ID | Requirement Description | Implementation Location | Verification Method | Tangible Evidence | Status | Outstanding Risk / Limitation |
|:---|:---|:---|:---|:---|:---:|:---|
| **REQ-G14-01** | Declarative Kubernetes manifest policy enforcement via Kyverno CLI across 10 security controls. | `security/policies/kyverno/`, `test_g14_security.py` | `kyverno test` (20 assertions), CI static validation | [`docs/evidence/G14/G14-acceptance-report.md`](../evidence/G14/G14-acceptance-report.md) | **PASSED_WITH_LIMITATIONS** | **Documented limitation:** Static pre-deployment validation in CI; no dynamic admission controller installed in Kind. Image registry rule checks hostnames, not digital signatures. |
| **REQ-G14-02** | GitOps secret encryption at rest using Mozilla SOPS and `age` asymmetric encryption. | `.sops.yaml`, `security/sops/`, `test_g14_sops.py` | Structure audit, dynamic dual-recipient decrypt/tamper tests | [`docs/evidence/G14/G14-acceptance-report.md`](../evidence/G14/G14-acceptance-report.md) | **PASSED** | Metadata cleartext (`encrypted_regex: '^(data\|stringData)$'`); zero private keys in Git. |
| **REQ-G14-03** | Dual-recipient encryption supporting independent emergency disaster recovery escrow key. | `.sops.yaml`, `synthetic-secrets.enc.yaml` | Independent decryption with Primary and Recovery identities | [`docs/evidence/G14/G14-acceptance-report.md`](../evidence/G14/G14-acceptance-report.md) | **PASSED_WITH_LIMITATIONS** | **Documented limitation:** Offline escrow custody stored outside Git; CI does not hold long-lived private keys. Inside Kubernetes, applied secrets decrypt into `etcd` in-memory. |
| **REQ-G14-04** | Pinned tool installation hardening with authentic SHA-256 release checksum verification. | `.github/workflows/ci.yml` | `sha256sum -c -` verification for Kyverno, SOPS, and age | [`docs/evidence/G14/G14-acceptance-report.md`](../evidence/G14/G14-acceptance-report.md) | **PASSED** | Tool version upgrades require updating pinned checksums in CI workflow. |
