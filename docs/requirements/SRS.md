# Software Requirements Specification (SRS) — ForgeOps Platform

**Document Version:** 1.0  
**Effective Date:** 2026-10-22  
**Status:** Approved for Implementation Baseline (Gate G00)  
**System Name:** ForgeOps Platform & ForgeTasks API

---

## 1. Introduction & Purpose

### 1.1 Purpose
This document defines the functional and non-functional requirements for the **ForgeOps Platform** and its core operational workload, the **ForgeTasks API**. It establishes the formal verification criteria for all 16 project implementation gates (G00–G15).

### 1.2 System Overview
ForgeOps is an end-to-end, zero-mandatory-cloud-cost DevOps, Platform Engineering, and SRE portfolio system running on a local developer workstation (Windows 11 with WSL2). It demonstrates:
- A production-grade Java/Spring Boot REST application backed by PostgreSQL.
- CI supply-chain security, vulnerability scanning, and immutable image publishing to GHCR.
- Pull-based GitOps promotion and reconciliation via Argo CD on local Kind Kubernetes.
- Infrastructure as Code with independent Terraform state and Ansible Linux VM configuration.
- Unified metrics, alerts, and structured log aggregation via Prometheus, Grafana, Alertmanager, Loki, and Grafana Alloy.
- Automated database disaster recovery, measured RTO/RPO exercises, and chaos resilience drills.

### 1.3 Scope & Boundaries
- **In Scope:** Local Docker Compose development, GitHub Actions CI, Kind Kubernetes, Helm, Argo CD, Prometheus, Grafana, Alertmanager, Grafana Alloy, Loki, Terraform local lab, Ansible SSH host management, Flyway schema migrations, and k6 load testing.
- **Out of Scope (Hard Non-Goals):** Paid cloud provider resources (AWS, Azure, GCP), public Internet ingress, multi-region distributed clustering, production SLA guarantees, commercial APM licenses, or microservice mesh proliferation.

---

## 2. Functional Requirements (ForgeTasks API)

### 2.1 User & Account Management (REQ-F-01)
- **REQ-F-01.1:** The system shall support local user accounts with unique usernames, BCrypt password hashing, and role assignment (`ROLE_USER`, `ROLE_ADMIN`).
- **REQ-F-01.2:** A test-only bootstrap user fixture shall be provisioned exclusively under the `test` and `dev` profiles and strictly excluded from release artifacts.
- **REQ-F-01.3 (Tenant Isolation & Anti-Enumeration):** Authenticated endpoints shall enforce owner-level isolation: a user shall not be permitted to read, modify, or delete projects or tasks belonging to another user. To prevent cross-tenant resource enumeration and timing attacks, unauthorized access attempts to another user's projects or tasks shall consistently return HTTP `404 Not Found` (identical to non-existent resources).

### 2.2 Project Management (REQ-F-02)
- **REQ-F-02.1:** Authenticated users shall create projects with a mandatory name (<= 120 chars) and optional description (<= 4000 chars).
- **REQ-F-02.2:** The system shall support paginated and sorted retrieval of projects owned by the authenticated caller.
- **REQ-F-02.3 (Conditional Update & Optimistic Concurrency Contract):** Project entities shall include a version field (`version BIGINT NOT NULL DEFAULT 0`). All mutating updates (`PATCH /api/v1/projects/{id}`) and deletes (`DELETE /api/v1/projects/{id}`) strictly require the `If-Match: "<version>"` HTTP request header:
  - If `If-Match` header is missing, the API shall return **HTTP 428 Precondition Required**.
  - If `If-Match` header does not match current database entity version, the API shall return **HTTP 412 Precondition Failed**.
  - If a concurrent database transaction race condition occurs during commit, the API shall return **HTTP 409 Conflict**.
  - Successful updates shall return HTTP 200 OK with the updated representation and new `ETag: "<new-version>"` response header. Successful deletes shall return HTTP 204 No Content.
- **REQ-F-02.4:** Deleting a project shall cascade or soft-delete associated tasks according to documented lifecycle policy.

### 2.3 Task Management (REQ-F-03)
- **REQ-F-03.1:** Users shall create tasks associated with a valid project owned by the caller.
- **REQ-F-03.2:** Tasks shall enforce title (<= 200 chars), optional description (<= 4000 chars), status (`TODO`, `IN_PROGRESS`, `BLOCKED`, `DONE`), priority (`LOW`, `MEDIUM`, `HIGH`), and optional UTC due date.
- **REQ-F-03.3:** The system shall support filtering and paginating tasks by project ID, status, priority, and creation timestamp.
- **REQ-F-03.4 (Task Conditional Update Contract):** Task updates (`PATCH /api/v1/tasks/{id}`) and deletes (`DELETE /api/v1/tasks/{id}`) shall enforce the identical conditional request contract (mandatory `If-Match`, returning 428 on missing header, 412 on version mismatch, 409 on transaction race condition, and 200 with updated `ETag` on success).

### 2.4 Persistence & Migrations (REQ-F-04)
- **REQ-F-04.1:** The database schema shall be versioned and managed exclusively using Flyway relational migrations.
- **REQ-F-04.2:** Schema migrations shall strictly follow the Expand/Contract pattern to ensure backward compatibility during application rollbacks.
- **REQ-F-04.3:** Primary keys shall be UUIDs; foreign keys and composite indexes (`(project_id, status, created_at DESC)`) shall be explicitly defined.
- **REQ-F-04.4 (Production vs. Seed Data Separation):** Production migrations (`classpath:db/migration`) shall contain only DDL schema definitions and structural indexes. Development and test sample data shall be strictly segregated into `classpath:db/dev-data` or profile-scoped initializer beans (`@Profile("dev")`), guaranteeing that production databases are never seeded with test credentials or mock data.

### 2.5 REST Contract, RFC 9457 & Diagnostics (REQ-F-05)
- **REQ-F-05.1:** All REST endpoints shall adhere to URL prefix `/api/v1/`.
- **REQ-F-05.2 (RFC 9457 Problem Details):** Error responses shall strictly adhere to RFC 9457 (Problem Details for HTTP APIs, `application/problem+json`) with standard fields: `type`, `title`, `status`, `detail`, `instance`, `requestId` (from SLF4J MDC), and ISO-8601 `timestamp`. Validation errors shall append an `invalidParams` array.
- **REQ-F-05.3 (Actuator & Management Protection):**
  - `/actuator/health/liveness`: Returns HTTP 200 `UP` reflecting JVM responsiveness without external I/O probes.
  - `/actuator/health/readiness`: Returns HTTP 200 `UP` only when the PostgreSQL connection pool (HikariCP) is operational (`SELECT 1`); returns HTTP 503 `DOWN` upon database disconnect.
  - `/actuator/prometheus`: Exposes Micrometer metrics (including SLA latency histograms for p50/p95/p99); restricted to authenticated scrape access or loopback.
  - Unsafe management endpoints (`/actuator/env`, `/actuator/beans`, `/actuator/heapdump`, `/actuator/configprops`) are strictly disabled to prevent credential and memory leaks.

---

## 3. Platform & Infrastructure Requirements

### 3.1 Containerization & Local Development (REQ-P-01)
- **REQ-P-01.1:** The application container shall use a multi-stage Dockerfile based on Eclipse Temurin JRE alpine, executing under a non-root UID/GID (e.g., `10001:10001`).
- **REQ-P-01.2:** The container image shall bake zero passwords, secrets, or Docker socket mounts into layers.
- **REQ-P-01.3:** `docker compose` shall orchestrate the API and PostgreSQL with health-dependent startup sequencing and persistent named volumes bound to `127.0.0.1`.

### 3.2 Continuous Integration & Supply Chain Security (REQ-P-02)
- **REQ-P-02.1:** GitHub Actions PR workflows shall run in an untrusted sandbox with `read-all` permissions, executing lint, unit/integration tests, Gitleaks, and Trivy scans without container publish privileges.
- **REQ-P-02.2:** Commits merged to `main` shall publish a versioned container image to GHCR, generating an immutable `sha256:...` digest and an SPDX/CycloneDX SBOM.
- **REQ-P-02.3:** A reproducible local CI equivalent (`make ci`) shall execute the test and scan suite offline.

### 3.3 Kubernetes, Helm & GitOps (REQ-P-03)
- **REQ-P-03.1:** Workloads shall run in local Kind Kubernetes clusters with namespace isolation (`forgeops-dev`, `forgeops-staging`).
- **REQ-P-03.2:** Helm charts shall define Deployments, Services, ConfigMaps, and ServiceAccounts, referencing secrets via `existingSecretName` without committing raw secret values.
- **REQ-P-03.3:** Argo CD shall manage application delivery via pull-based GitOps. Promotion shall occur via reviewed Pull Requests updating image digests in Git values files.
- **REQ-P-03.4:** Application rollback shall be achieved declaratively by reverting the Git desired-state commit.

### 3.4 Infrastructure as Code (Terraform) (REQ-P-04)
- **REQ-P-04.1:** Terraform shall manage a local Docker diagnostic fixture (`local-docker-lab`) with pinned `kreuzwerker/docker` provider (v4.6.0) and local state excluded from Git.
- **REQ-P-04.2:** Terraform shall manage the initial platform bootstrap (`cluster-bootstrap`), deploying the Argo CD Helm release onto a running Kind cluster without overlapping application workload ownership.
- **REQ-P-04.3:** Terraform destructive actions shall never destroy Kind cluster nodes or Docker Compose databases.

### 3.5 Configuration Management (Ansible) (REQ-P-05)
- **REQ-P-05.1:** Ansible Core (2.17.7) shall manage an independent Ubuntu Linux guest VM over SSH using key-based authentication.
- **REQ-P-05.2:** Ansible roles (`baseline`, `users`, `ssh-hardening`, `firewall`, `nginx`) shall enforce idempotence: a second execution of `site.yml` shall report `changed=0`.
- **REQ-P-05.3:** Per project operating rules, a Docker container simulation shall never be substituted for the Ansible Linux guest VM.

### 3.6 Observability & Centralized Logging (REQ-P-06)
- **REQ-P-06.1:** Prometheus shall scrape Actuator metrics and Kubernetes state with a retention limit of 24 hours (Core profile).
- **REQ-P-06.2:** Alertmanager shall receive Prometheus alerts and route them to local test receivers.
- **REQ-P-06.3:** Container logs shall be harvested using **Grafana Alloy** (rejecting EOL Promtail) and forwarded to Grafana Loki.
- **REQ-P-06.4:** Grafana dashboards shall display the Golden Signals (latency, traffic, errors, saturation) and correlate logs with failed HTTP requests via `requestId`.

### 3.7 Disaster Recovery & Backup (REQ-P-07)
- **REQ-P-07.1:** Database backups shall be executed host-side via `pg_dump` (`make backup-db`), generating timestamped, compressed dumps with SHA256 checksums stored in `~/.config/forgeops/backups/`.
- **REQ-P-07.2:** Automated backup verification (`make verify-backup`) shall restore dumps into a disposable scratch database and validate table schemas, row counts, and foreign keys.
- **REQ-P-07.3:** The system shall achieve a measured Recovery Time Objective (RTO) of ≤60 minutes and Recovery Point Objective (RPO) of ≤24 hours during cluster loss drills.

---

## 4. Non-Functional Requirements (Lab Engineering Targets)

| ID | Category | Requirement Specification | Verification Method |
|---|---|---|---|
| **NFR-SEC-01** | Secrets Hygiene | Zero credentials, tokens, private keys, or `.tfstate` files committed to Git. | Automated Gitleaks scan in CI & pre-commit |
| **NFR-SEC-02** | Least Privilege | Containers run non-root; Kubernetes ServiceAccounts disable token automounting by default. | Trivy container scan & pod spec audit |
| **NFR-SEC-03** | Network Exposure | All web UIs (Argo CD, Grafana) and APIs bind exclusively to `127.0.0.1` / loopback. | Nmap external port scan from LAN |
| **NFR-PERF-01**| Performance | p95 HTTP response latency < 500 ms under baseline k6 load (50 VUs, 2m) on warmed host. | k6 load test report + Prometheus histogram |
| **NFR-REL-01** | Reliability | HTTP error rate < 1.0% during baseline load execution; stateless pod kill auto-recovers. | k6 test execution + DR-01 drill |
| **NFR-RES-01** | Host Footprint | Active Docker workloads consume <= 4.0 GiB RAM in Core profile; disk cleanup alert at < 2 GB. | `docker stats`, `free -h`, `df -h` |
| **NFR-COV-01** | Test Coverage | Application service & business logic test coverage ≥ 80% with JaCoCo enforcement in `pom.xml`. | Maven `verify` goal (`jacoco:check`) |
| **NFR-TEST-01**| Real DB Testing | All repository and API integration tests execute against real PostgreSQL 16 via Testcontainers. | Maven test suite execution |
| **NFR-TEST-02**| Concurrency Testing | Concurrent threads submitting stale versions must deterministically trigger HTTP 409 Conflict. | Integration test `ConcurrencyLockingTest` |
| **NFR-MIG-01** | Migration Safety | Database migrations must execute cleanly on empty database and be idempotent on restart. | Integration test `MigrationTest` |
