# ForgeOps Technology Compatibility Matrix

**Effective Date:** 2026-10-22  
**Review Gate:** G00 Architecture Baseline  
**Update Policy:** Pinned immutable versions or SHA256 digests; strict "no blind latest" policy.

---

## 1. Core Toolchain & Runtimes

| Component | Target Version | Selection Rationale | Official Upstream Reference | Pinning / Locking Strategy |
|---|---|---|---|---|
| **Java JDK** | Eclipse Temurin OpenJDK 21.0.x LTS | Standard LTS release for modern Spring Boot; virtual threads support, mature container integration. | https://adoptium.net/temurin/releases/ | Docker base: `eclipse-temurin:21-jre-alpine`; local toolchain JDK 21 |
| **Spring Boot** | 4.1.2 (BOM Managed) | Flagship actively maintained baseline (released 2026-10-23); modularized `spring-boot-starter-webmvc`, native RFC 9457 ProblemDetails, Micrometer Actuator, Jakarta EE 11 / Servlet 6.1. Drop-in patch for 4.1.1. | https://spring.io/projects/spring-boot | Managed via Maven `spring-boot-starter-parent:4.1.2` BOM (zero ad-hoc dependency versions) |
| **PostgreSQL** | 16.6 (or 17.x LTS) | Mature relational DB with ACID compliance, robust jsonb, pg_dump/pg_restore reliability. | https://www.postgresql.org/docs/16/release-16-6.html | OCI digest pin: `postgres:16-alpine@sha256:...`; JDBC driver BOM-managed |
| **Flyway** | 11.x (BOM Managed) | Deterministic, forward-compatible relational schema migrations. Production migrations segregated from dev seeds. | https://documentation.red-gate.com/fd/release-notes-184127444.html | Managed by Spring Boot BOM (`flyway-core`, `flyway-database-postgresql`) |
| **Testcontainers** | 2.x (Standardized Coordinates) | Isolated disposable PostgreSQL 16 container for reliable integration and migration verification. Standardized 2.x artifact naming. | https://java.testcontainers.org/ | `org.testcontainers:testcontainers-postgresql` & `org.testcontainers:testcontainers-junit-jupiter` |
| **JaCoCo** | 0.8.12 | Enforces reproducible code coverage gate (≥80% on business/service code). Compatible with Java 21 bytecode. | https://www.jacoco.org/jacoco/trunk/doc/changes.html | Maven plugin version pinned in `pom.xml` |
| **Python** | 3.12.3 | Default on Ubuntu 24.04 LTS; stable runtime for Ansible and operational automation. | https://docs.python.org/3.12/ | Locked via system package & virtual environment |
| **GNU Make** | 4.3 | Ubiquitous build automation and entrypoint across Linux & WSL environments. | https://www.gnu.org/software/make/ | Standard system package |

---

## 2. Infrastructure as Code & Configuration Management

| Component | Target Version | Selection Rationale | Official Upstream Reference | Pinning / Locking Strategy |
|---|---|---|---|---|
| **Terraform CLI** | v1.10.4 / v1.11.x | Robust local state engine, provider locking, declarative plan/apply workflows. | https://developer.hashicorp.com/terraform/downloads | Locked binary + `.terraform.lock.hcl` |
| **Terraform Docker Provider** | `kreuzwerker/docker` ~> 4.6.0 | Reliable local container and network provisioning without cloud credentials. | https://registry.terraform.io/providers/kreuzwerker/docker/latest | Pinned provider in `versions.tf` + lockfile |
| **Ansible Core** | 2.17.7 | Idempotent automation, SSH transport, Jinja2 templating, check-mode support. | https://docs.ansible.com/ansible/latest/roadmap/COLLECTIONS_2_17.html | Pinned in `requirements.txt` / pip freeze |
| **Ansible Collections** | `ansible.posix` 1.6.x, `community.general` 9.x | Standard Linux host management modules (firewall, users, systemd). | https://galaxy.ansible.com/ | Pinned via `infrastructure/ansible/requirements.yml` |

---

## 3. Container Runtime, Kubernetes & GitOps

| Component | Target Version | Selection Rationale | Official Upstream Reference | Pinning / Locking Strategy |
|---|---|---|---|---|
| **Docker Engine** | 29.5.3 (API 1.54) | Installed Docker Desktop WSL2 engine; container standard. | https://docs.docker.com/engine/release-notes/ | Controlled by host Docker Desktop installer |
| **Kind (Kubernetes in Docker)** | v0.30.0 - v0.33.0 | Zero-cost local cluster with multi-node simulation capability. | https://github.com/kubernetes-sigs/kind/releases | Binary pin in `scripts/cluster/create.sh` |
| **Kubernetes Node Image** | `kindest/node:v1.31.2` or `v1.32.x` | Stable Kind node image compatible with modern workloads and CNI. | https://hub.docker.com/r/kindest/node/tags | Explicit Kind configuration image digest |
| **kubectl** | v1.34.1 | Installed client CLI; backwards compatible with Kubernetes 1.30-1.34. | https://kubernetes.io/docs/tasks/tools/ | Client binary installed on host & WSL |
| **Helm** | v3.16.x / v3.17.x | Standard Kubernetes package manager; templating and release tracking. | https://github.com/helm/helm/releases | Pinned binary download |
| **Argo CD** | v3.5.6 (Chart ~> 7.x) | Pull-based declarative GitOps controller; automated drift detection and self-heal. | https://github.com/argoproj/argo-cd/releases | Pinned Helm chart version in bootstrap module |
| **Cilium CNI** | v1.16.x (Capstone/Clean profile) | eBPF-based CNI providing verifiable NetworkPolicy enforcement in Kind. | https://docs.cilium.io/en/stable/installation/kind/ | Pinned Helm chart in `platform/kind/cilium.yaml` |

---

## 4. Observability Stack

| Component | Target Version | Selection Rationale | Official Upstream Reference | Pinning / Locking Strategy |
|---|---|---|---|---|
| **Prometheus** | v2.55.x / v3.x | Industry standard metrics collection, TSDB, PromQL, Alertmanager integration. | https://prometheus.io/docs/introduction/overview/ | Helm chart `prometheus-community/prometheus` |
| **Grafana** | v11.3.x | Observability dashboards as code, multi-datasource correlation (Prometheus + Loki). | https://grafana.com/docs/grafana/latest/release-notes/ | Helm chart `grafana/grafana` |
| **Alertmanager** | v0.27.x / v0.28.x | Deduplication, grouping, and routing of Prometheus alerts to local receivers. | https://prometheus.io/docs/alerting/latest/alertmanager/ | Bundled with Prometheus Helm release |
| **Grafana Alloy** | v1.5.x / v1.x | **Direct replacement for EOL Promtail** (sunset March 2, 2026). Native Kubernetes pod log collector. | https://grafana.com/docs/alloy/latest/ | Helm chart `grafana/alloy` |
| **Grafana Loki** | v3.2.x / v3.3.x | Horizontally-scalable, logQL-powered log aggregation system with bounded label indexing. | https://grafana.com/docs/loki/latest/ | Helm chart `grafana/loki` |

---

## 5. Security & Verification Tooling

| Component | Target Version | Selection Rationale | Official Upstream Reference | Pinning / Locking Strategy |
|---|---|---|---|---|
| **Trivy** | v0.58.x / v0.59.x | Comprehensive vulnerability, secret, misconfiguration, and SBOM scanner. | https://github.com/aquasecurity/trivy/releases | Pinned GitHub Action & CLI binary |
| **Gitleaks** | v8.21.x / v8.22.x | Fast, regex-based secret detection preventing credential leaks into git history. | https://github.com/gitleaks/gitleaks/releases | Pre-commit hook & pinned CI action |
| **k6** | v0.55.x | Modern load and resilience testing tool; scriptable in JavaScript, low resource footprint. | https://github.com/grafana/k6/releases | Pinned binary executable |
| **Testcontainers Java** | 1.20.x | Real containerized PostgreSQL database testing for unit/integration tests. | https://java.testcontainers.org/ | Maven test dependency in `pom.xml` |

---

## 6. Upgrade & Maintenance Policy

1. **No Blind "Latest":** Every container image, Helm chart, GitHub Action, and binary must have an explicit pinned version or SHA256 digest.
2. **Single Component Upgrades:** Upgrade one component at a time, followed by targeted acceptance tests (`make test`).
3. **Deprecation Tracking:** Promtail is strictly forbidden due to March 2026 EOL; Grafana Alloy is the designated log collection pipeline.
4. **Lockfile Governance:** `.terraform.lock.hcl`, `requirements.yml`, and Maven dependency locks must be committed to Git.
