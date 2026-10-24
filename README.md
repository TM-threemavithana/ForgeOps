# ForgeOps — Self-Hosted DevOps & Platform Engineering Lab

[![Java](https://img.shields.io/badge/Java-21%20LTS-orange.svg)](https://adoptium.net/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.1.2-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)
[![Gate Status](https://img.shields.io/badge/Gate%20G01-PASSED-success.svg)](docs/evidence/G01/acceptance.md)

ForgeOps is a professional, production-grade local DevOps and Platform Engineering portfolio project. It is designed to demonstrate the complete, robust software delivery lifecycle:

$$\text{Development} \longrightarrow \text{Automated Testing} \longrightarrow \text{Containerization} \longrightarrow \text{CI/CD} \longrightarrow \text{IaC} \longrightarrow \text{Kubernetes} \longrightarrow \text{GitOps} \longrightarrow \text{Observability} \longrightarrow \text{Reliability \& DR}$$

Operating under a strict **zero paid cloud dependency** model, the entire platform runs predictably on local workstations using Linux/WSL2, Docker, Kind, Terraform, Ansible, and Argo CD.

---

## What is ForgeTasks?

**ForgeTasks** is the core backend service of ForgeOps. Built with **Java 21 LTS** and **Spring Boot 4.1.2**, it provides a multi-tenant task and project management REST API backed by **PostgreSQL 16**.

### Architectural Highlights (Phase G01)

- **Domain Model:** Multi-tenant hierarchy (`Account` $\to$ `Project` $\to$ `Task`) with strict UUID primary keys and database foreign-key constraints.
- **Tenant Isolation:** Enforced at the repository query level. Accessing a non-owned project or task strictly returns `HTTP 404 Not Found` to prevent resource enumeration attacks.
- **Optimistic Concurrency & Lost Update Prevention (RFC 7232/9110):**
  - Strong ETags derived from entity versions (`ETag: "<version>"`).
  - Mutating operations (`PATCH`, `DELETE`) require the `If-Match` header.
  - Missing precondition returns `HTTP 428 Precondition Required`.
  - Stale precondition returns `HTTP 412 Precondition Failed`.
- **Standardized Error Handling (RFC 9457):** All API errors and validation failures produce `application/problem+json` `ProblemDetail` structures enriched with correlation tracking.
- **Traceability & Correlation:** `RequestCorrelationFilter` extracts or generates an `X-Request-ID`, propagating it into SLF4J MDC logs and response headers.
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
| **G02** | Multi-Stage Containerization & Docker Compose Stack | *Planned* | Deferred to Gate G02 |
| **G03** | Local & GitHub Actions CI Pipelines | *Planned* | Deferred to Gate G03 |
| **G04** | Ansible Linux Host Configuration Management | *Planned* | Deferred to Gate G04 |
| **G05** | Terraform Local Docker Lab Fixture | *Planned* | Deferred to Gate G05 |
| **G06** | Local Kind Kubernetes Cluster & CNI | *Planned* | Deferred to Gate G06 |
| **G07** | Helm Chart Packaging & Parameterization | *Planned* | Deferred to Gate G07 |
| **G08** | Argo CD GitOps Bootstrap & Continuous Sync | *Planned* | Deferred to Gate G08 |
| **G09** | Prometheus Metrics & Alertmanager Alerting Rules | *Planned* | Deferred to Gate G09 |
| **G10** | Grafana Dashboards, Loki & Alloy Pod Log Harvesting | *Planned* | Deferred to Gate G10 |
| **G11** | Security Hardening (Trivy, Gitleaks, RBAC, NetworkPolicy) | *Planned* | Deferred to Gate G11 |
| **G12** | SRE Load & Chaos Testing (k6, Pod Failure Scenarios) | *Planned* | Deferred to Gate G12 |
| **G13** | Database Disaster Recovery, Backup & Restoration DR Drill | *Planned* | Deferred to Gate G13 |
| **G14** | Complete System Teardown & Reconstruction Runbook | *Planned* | Deferred to Gate G14 |
| **G15** | Final Project Showcase, Architectural Portfolio & Video | *Planned* | Deferred to Gate G15 |

> [!NOTE]
> Future gates G02–G15 are planned in the [Master Implementation Plan](docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md) and will be implemented sequentially upon review approval.

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

---

## Local Execution & Verification

### 1. Launch Local PostgreSQL Database

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
