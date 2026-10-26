# ForgeOps — Self-Hosted DevOps & Platform Engineering Lab

[![Java](https://img.shields.io/badge/Java-21%20LTS-orange.svg)](https://adoptium.net/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.1.2-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)
[![Gate G02](https://img.shields.io/badge/Gate%20G02-PASSED-success.svg)](docs/evidence/G02/acceptance.md)
[![Gate G03](https://img.shields.io/badge/Gate%20G03-PASSED-success.svg)](docs/evidence/G03/acceptance.md)
[![CI](https://github.com/TM-threemavithana/ForgeOps/actions/workflows/ci.yml/badge.svg)](https://github.com/TM-threemavithana/ForgeOps/actions/workflows/ci.yml)

ForgeOps is a professional, production-grade local DevOps and Platform Engineering portfolio project. It is designed to demonstrate the complete, robust software delivery lifecycle:

$$\text{Development} \longrightarrow \text{Automated Testing} \longrightarrow \text{Containerization} \longrightarrow \text{CI/CD} \longrightarrow \text{IaC} \longrightarrow \text{Kubernetes} \longrightarrow \text{GitOps} \longrightarrow \text{Observability} \longrightarrow \text{Reliability \& DR}$$

Operating under a strict **zero paid cloud dependency** model, the entire platform runs predictably on local workstations using Linux/WSL2, Docker, Kind, Terraform, Ansible, and Argo CD.

---

## What is ForgeTasks?

**ForgeTasks** is the core backend service of ForgeOps. Built with **Java 21 LTS** and **Spring Boot 4.1.2**, it provides a multi-tenant task and project management REST API backed by **PostgreSQL 16**.

### Architectural Highlights (Phase G01 & G02)

- **Domain Model:** Multi-tenant hierarchy (`Account` $\to$ `Project` $\to$ `Task`) with strict UUID primary keys and database foreign-key constraints.
- **Tenant Isolation:** Enforced at the repository query level. Accessing a non-owned project or task strictly returns `HTTP 404 Not Found` to prevent resource enumeration attacks.
- **Optimistic Concurrency & Lost Update Prevention (RFC 7232/9110):**
  - Strong ETags derived from entity versions (`ETag: "<version>"`).
  - Mutating operations (`PATCH`, `DELETE`) require the `If-Match` header.
  - Missing precondition returns `HTTP 428 Precondition Required`.
  - Stale precondition returns `HTTP 412 Precondition Failed`.
- **Standardized Error Handling (RFC 9457):** All API errors and validation failures produce `application/problem+json` `ProblemDetail` structures enriched with correlation tracking.
- **Traceability & Correlation:** `RequestCorrelationFilter` extracts or generates an `X-Request-ID`, propagating it into SLF4J MDC logs and response headers.
- **Hardened Multi-Stage Containerization:**
  - Minimal JRE runtime on Alpine Linux (`eclipse-temurin:21-jre-alpine`).
  - Strict non-root execution (`10001:10001`), `no-new-privileges:true`, and `cap_drop: [ALL]`.
  - Secure out-of-band secret injection using Docker Compose secrets and Spring Boot configuration trees (`optional:configtree:/run/secrets/`).
  - Scoped loopback exposure (`127.0.0.1:18080:8080`) with internal-only PostgreSQL connectivity.
- **Observability Foundations:**
  - Liveness probe at `/actuator/health/liveness` (JVM state, decoupled from database).
  - Readiness probe at `/actuator/health/readiness` (PostgreSQL connectivity check).
  - Prometheus metrics scrape at `/actuator/prometheus` (request latencies, HikariCP pool metrics, JVM memory).
- **Stateless Security:** HTTP Basic authentication with BCrypt-12 password hashing.

---

## Current Implementation Status

Implementation progress is governed by strict gated reviews (Gates G00 through G15):

| Gate | Domain | Status | Evidence |
|---|---|---|---|
| **G00** | Preflight, Hardware Feasibility & Architecture Baseline | **PASSED** | [G00 Preflight Report](docs/evidence/G00-preflight.md) |
| **G01** | ForgeTasks API Backend & PostgreSQL Schema Correctness | **PASSED** | [G01 Acceptance Report](docs/evidence/G01/acceptance.md) |
| **G02** | Multi-Stage Containerization & Docker Compose Stack | **PASSED** | [G02 Acceptance Report](docs/evidence/G02/acceptance.md) |
| **G03** | Local & GitHub Actions CI Pipelines, Trust Boundaries & GHCR | **PASSED** | [G03 Acceptance Report](docs/evidence/G03/acceptance.md) |
| **G04** | Ansible Linux Host Configuration Management | **PASSED** | [G04 Acceptance Report](docs/evidence/G04/readiness.md) |
| **G05** | Terraform Local Docker Lab Fixture | **PASSED** | [G05 Acceptance Report](docs/evidence/G05/readiness.md) |
| **G06** | Local Kind Kubernetes Cluster & CNI | **PASSED_LIM** | [G06 Acceptance Report](docs/evidence/G06/readiness.md) |
| **G07** | Helm Chart Packaging & Parameterization | **PASSED** | [G07 Acceptance Report](docs/evidence/G07/readiness.md) |
| **G08** | Argo CD GitOps Bootstrap & Continuous Sync | *Planned* | Deferred to Gate G08 |
| **G09** | Prometheus Metrics & Alertmanager Alerting Rules | *Planned* | Deferred to Gate G09 |
| **G10** | Grafana Dashboards, Loki & Alloy Pod Log Harvesting | *Planned* | Deferred to Gate G10 |
| **G11** | Security Hardening (Trivy, Gitleaks, RBAC, NetworkPolicy) | *Planned* | Deferred to Gate G11 |
| **G12** | SRE Load & Chaos Testing (k6, Pod Failure Scenarios) | *Planned* | Deferred to Gate G12 |
| **G13** | Database Disaster Recovery, Backup & Restoration DR Drill | *Planned* | Deferred to Gate G13 |
| **G14** | Complete System Teardown & Reconstruction Runbook | *Planned* | Deferred to Gate G14 |
| **G15** | Final Project Showcase, Architectural Portfolio & Video | *Planned* | Deferred to Gate G15 |

> [!NOTE]
> Gates G08–G15 are planned in the [Master Implementation Plan](docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md) and will be implemented sequentially upon review approval.

---

## Getting Started

### Prerequisites

- **OS:** Linux or Windows 11 with WSL2 (Ubuntu 24.04 LTS recommended)
- **Java:** OpenJDK 21 LTS (`java` and `javac`)
- **Docker:** Docker Desktop or Docker Engine $\ge 24.x$
- **Make:** GNU Make

Check your local environment using the automated preflight target:

```bash
make doctor
```

---

## CI/CD Pipeline (Gate G03)

G03 implements a secure, layered CI/CD system with an explicit trust boundary between automated CI and controlled CD.

### CI — Automatic (Push & Pull Request)

Every push to `master` and every pull request automatically triggers:

| Job | What it does |
|---|---|
| **Build & Test** | `./mvnw clean verify` — 43 tests, JaCoCo ≥80% coverage gate |
| **Docker Build Validate** | Multi-stage build (no push), non-root UID 10001 check, label inspection |
| **Trivy Scan** | Zero CRITICAL unfixed CVEs gate; SARIF uploaded to GitHub Code Scanning |
| **Gitleaks** | Full repository history secret leak detection |
| **CI Gate** | Aggregated required status check — blocks merge if any job fails |

The CI workflow **never** pushes to GHCR. All jobs run with `contents: read` minimum permissions.

### CD — Controlled Publish to GHCR

Image publishing requires **manual** `workflow_dispatch` with explicit confirmation:

```
Actions → Publish to GHCR → Run workflow
  git_sha:    <full commit SHA>
  semver_tag: 1.0.0        (optional)
  confirm:    PUBLISH      (must type this exactly)
```

The publish workflow re-runs Trivy before any push. Published images include SLSA Level 2 provenance attestation and SBOM.

```bash
# Pull by immutable SHA256 digest (never use floating :latest in production):
docker pull ghcr.io/TM-threemavithana/forgetasks-api@sha256:<digest>
```

### Local CI Replication

```bash
# Full local CI (Maven verify + Docker build + optional Trivy/Gitleaks)
make ci-local

# Standalone Trivy scan (requires trivy installed)
make trivy-scan

# Lint workflow YAML files (requires actionlint installed)
make actionlint
```

### Branch Protection Setup

Configure in GitHub → Settings → Branches → `master`:
- [x] Require status checks: **CI Gate**
- [x] Require branches to be up to date before merging

---

## Building and Testing


The project uses a project-local Maven Wrapper (`mvnw`) requiring no pre-installed Maven.

### 1. Run Unit & Integration Tests

All integration tests utilize **Testcontainers** to spin up an isolated, disposable PostgreSQL 16 container:

```bash
make test-api
# Or directly:
cd apps/forgetasks-api && ./mvnw clean verify
```

### 2. Code Coverage

JaCoCo enforces a strict **$\ge 80\%$** code coverage requirement on instructions and branches:

- **Verified Instruction Coverage:** **94.09%**
- **Verified Branch Coverage:** **91.23%**

HTML reports are generated at `apps/forgetasks-api/target/site/jacoco/index.html`.

### 3. Package the Application

```bash
make build-api
# Or directly:
cd apps/forgetasks-api && ./mvnw clean package -DskipTests
```

## Docker Compose Stack (Phase G02)

The primary local development and verification environment runs ForgeTasks API and PostgreSQL 16 via Docker Compose in an isolated namespace (`forgeops-g02`).

### 1. Initialize Local Secrets
Generate an untracked local database credential (permissions 0600) into `secrets/db_password.txt`:

```bash
make setup-secrets
# Or directly:
./scripts/setup_secrets.sh
```

### 2. Build the Multi-Stage Container Image
Build the hardened, non-root `forgetasks-api:1.0.0` image:

```bash
make compose-build
# Or directly:
docker compose build
```

### 3. Start the Local Compose Stack
Start PostgreSQL and ForgeTasks API in background mode:

```bash
make compose-up
# Or directly:
docker compose up -d
```

The stack initializes the dedicated network (`forgeops-g02-net`), waits for PostgreSQL to become healthy via `pg_isready`, and starts ForgeTasks API bound strictly to loopback (`127.0.0.1:18080:8080`).

### 4. Inspect Status and Logs
```bash
make compose-ps
make compose-logs
```

### 5. Run Automated Live Verification
```bash
# 15-point live API contract, concurrency, and security verification
./scripts/verify_g02_stack.sh

# Persistence, container recreation, API restart & DB recovery drill
./scripts/verify_g02_reliability.sh
```

### 6. Vulnerability Scanning (Trivy)
Scan the runtime image using official Trivy without installing untrusted host binaries:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --pkg-types os --severity CRITICAL,HIGH,MEDIUM,LOW forgetasks-api:1.0.0
```

### 7. Gracefully Stop the Stack (Preserve Data)
```bash
make compose-down
# Or directly:
docker compose down
```
*Note: Persistent data is preserved in the named Docker volume `forgeops-g02-postgres-data`. Never use `-v` unless a complete destructive reset is intended.*

---

## Standalone Local Execution (Phase G01 Legacy)

Run an isolated PostgreSQL 16 database instance:

```bash
docker run -d --name forgetasks-local-db \
  -e POSTGRES_DB=forgetasks \
  -e POSTGRES_USER=forge \
  -e POSTGRES_PASSWORD=forgesecret \
  -p 5434:5432 \
  postgres:16-alpine
```

### 2. Start ForgeTasks API

Launch the packaged Spring Boot application:

```bash
SPRING_DATASOURCE_URL=jdbc:postgresql://127.0.0.1:5434/forgetasks \
SPRING_DATASOURCE_USERNAME=forge \
SPRING_DATASOURCE_PASSWORD=forgesecret \
PORT=8080 \
java -jar apps/forgetasks-api/target/forgetasks-api-1.0.0-SNAPSHOT.jar
```

Flyway will automatically execute database migrations (`V1__init_schema.sql`), establishing tables and indexes.

### 3. Verify Endpoints

Run the automated verification suite:

```bash
./scripts/verify_runtime.sh
```

Or execute manual `curl` requests:

#### Check Health Probes
```bash
# Liveness (process health)
curl -i http://localhost:8080/actuator/health/liveness

# Readiness (PostgreSQL connectivity)
curl -i http://localhost:8080/actuator/health/readiness
```

#### Register Account
```bash
curl -i -X POST http://localhost:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"dev_lead","password":"Password123!","email":"lead@example.com"}'
```

#### Create a Project
```bash
curl -i -X POST http://localhost:8080/api/v1/projects \
  -u dev_lead:Password123! \
  -H "Content-Type: application/json" \
  -d '{"name":"Kubernetes Migration","description":"Production platform upgrade"}'
```
*Note the returned `ETag` header (e.g. `ETag: "0"`).*

#### Mutate Project with Conditional Request
```bash
curl -i -X PATCH http://localhost:8080/api/v1/projects/<PROJECT_ID> \
  -u dev_lead:Password123! \
  -H "If-Match: \"0\"" \
  -H "Content-Type: application/json" \
  -d '{"description":"Production platform upgrade - Wave 1"}'
```

---

## Repository Structure

```text
ForgeOps/
├── .github/                      # CI/CD workflows and repository governance
├── apps/
│   └── forgetasks-api/           # ForgeTasks Spring Boot 4.1.2 application
│       ├── pom.xml               # Maven POM with pinned coordinates
│       ├── mvnw                  # Linux/WSL Maven Wrapper
│       └── src/
│           ├── main/
│           │   ├── java/         # Clean modular domain/service/api code
│           │   └── resources/    # Flyway migrations and YAML configs
│           └── test/             # Unit and PostgreSQL Testcontainers tests
├── docs/
│   ├── adr/                      # Architectural Decision Records (ADR 0001–0013)
│   ├── evidence/
│   │   ├── G00-preflight.md      # G00 environment verification
│   │   └── G01/                  # G01 acceptance evidence and curl logs
│   ├── requirements/             # SRS and Requirements Traceability Matrix
│   ├── compatibility-matrix.md   # Technology version compatibility matrix
│   └── FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md # Master plan G00–G15
├── scripts/                      # Operational automation scripts
├── Makefile                      # Standardized project tasks
└── AGENTS.md                     # Agent operating rules and safety constraints
```
