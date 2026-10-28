# ForgeOps: Project Overview & Executive Summary

## 1. Executive Summary

**ForgeOps** is a production-inspired, self-hosted DevOps, DevSecOps, and Platform Engineering demonstration platform designed to model the full software delivery and operational lifecycle of a multi-tier microservice without paid cloud dependencies.

Built from first principles, ForgeOps proves that enterprise-grade reliability, GitOps delivery, three-pillar observability, automated disaster recovery, and policy-as-code security can be designed, deployed, and rigorously tested on a single-node, resource-governed developer workstation (Windows 11 with WSL2 / Linux).

```
   +-----------------------------------------------------------------------------------+
   |                                 FORGEOPS PLATFORM                                 |
   |                                                                                   |
   |   [Developer Push] ---> [GitHub Actions CI/CD] ---> [GHCR Immutable Digest]        |
   |                                                               |                   |
   |                                                               v                   |
   |   [Grafana UI / Alerts] <--- [Loki / Tempo / Prom] <--- [Argo CD GitOps Engine]   |
   |                                                               |                   |
   |                                                               v                   |
   |   [PostgreSQL DB + PVC] <------------------------------ [ForgeTasks API Pods]     |
   |             |                                                                     |
   |             +---> [Automated pg_dump / pg_restore DR to forgeops-dr-lab]          |
   +-----------------------------------------------------------------------------------+
```

---

## 2. Core Problem Statement

Modern enterprise engineering organizations face significant friction in junior-to-mid engineering onboarding and platform skill acquisition:
1. **Cloud Cost Prohibitions:** Cloud environments (AWS, GCP, Azure) incur recurring operational costs, egress charges, and managed service fees that prevent hands-on chaos and recovery experimentation.
2. **Abstracted Infrastructure ("Black Box Syndrome"):** Fully managed services hide the underlying mechanics of container networking, storage volumes, TLS handshakes, ingress routing, and process lifecycle management.
3. **Disjointed Tooling:** Security scanning, continuous deployment, distributed tracing, metrics, logging, and disaster recovery are frequently treated as isolated silos rather than a cohesive control loop.

**ForgeOps solves this** by implementing a completely reproducible, zero-cloud architecture where every boundary—from kernel cgroups to GitOps controllers—is auditable, observable, and testable locally.

---

## 3. Technology Stack & Ownership Boundaries

To prevent tool overlap and resource contention, ForgeOps enforces a strict **single-owner-per-resource** governance model:

| Functional Domain | Primary Technology | Exact Version | Ownership & Responsibility |
|:---|:---|:---|:---|
| **Workload / Runtime** | Java 21 LTS / Spring Boot 4.1.2 | `4.1.2` | REST API, Flyway migrations, Micrometer metrics, OpenTelemetry instrumentation. |
| **Persistence** | PostgreSQL | `16-alpine` | Relational storage, ACID transactions, transactional indexes, volume persistence. |
| **Container Engine** | Docker Engine & Compose | `27.x` | Local developer inner loop, isolated network fixtures, synthetic DR targets. |
| **Kubernetes Orchestrator** | Kubernetes in Docker (Kind) | `v1.34.11` | Single-node control plane and worker; owns cluster lifecycle via shell scripts. |
| **Infrastructure-as-Code** | HashiCorp Terraform | `v1.10.4` | Manages local container infrastructure and Argo CD fixture bootstrapping. |
| **Configuration Management**| Ansible Core | `2.17.7` | Linux guest OS baseline configuration, security hardening, and SSH control. |
| **GitOps Continuous Delivery**| Argo CD | `v3.5.6` | Declarative synchronization of Kubernetes manifests and Helm chart releases. |
| **Packaging & Templating** | Helm | `v3.19.5` | Environment-specific parameterization (`forgeops-dev`, `staging`). |
| **Metrics & Alerting** | Prometheus & Alertmanager | `v3.15.0 / v0.34.1` | Pull-based scrape loop, recording rules, multi-stage alert dispatch. |
| **Log Aggregation** | Grafana Loki & Alloy | `3.4.2 / v1.21.2` | Structured log shipping, redaction pipelines, Loki LogQL indexing. |
| **Distributed Tracing** | OpenTelemetry Java & Tempo | `v2.1.0 / 2.9.0` | W3C tracecontext propagation, gRPC span export, Grafana Trace-to-Logs correlation. |
| **Policy-as-Code** | Kyverno CLI | `v1.19.2` | Client-side static validation of Kubernetes Pod security contexts in CI. |
| **Encrypted Secrets** | SOPS + age | `v3.13.3 / v1.2.1` | Git-safe secret encryption using asymmetric public-key cryptography and dual-key escrow. |
| **Reliability & DR** | k6 & Bash / pg_dump | `v1.8.2` | Threshold-driven load injection, fault simulation, automated transactional recovery. |

---

## 4. Key Verified Engineering Achievements

The platform has undergone rigorous, evidence-backed verification across all 15 gates:

* **SRE Load & Chaos Injection (Gate G12):**
  * Executed 5 progressive k6 load scenarios generating **2,275 HTTP requests** with **zero HTTP errors (0.00% failure rate)**.
  * Aggregate suite latency: **p50: 4.21 ms, p95: 6.82 ms, p99: 28.10 ms, max: 35.03 ms** under a single-backend port-forward connection.
  * Verified resilience across 5 controlled failure experiments:
    1. *Stateless Pod Termination:* Detected in 1.69s; restored full 2/2 ready state in **52.86 seconds** with zero dropped connections.
    2. *Readiness Probe Failure Injection:* Surge pod excluded from Service endpoints; probe restored in **706 ms**.
    3. *Invalid Image Rollout Guard:* Nonexistent image tag halted in `ErrImagePull` while existing replicas served traffic; restored via rollout undo in **813 ms**.
    4. *Bounded Resource Pressure:* Handled 1,052 requests up to 10 VUs / 20 req/s ceiling with 0 OOMKills and 0 container restarts.
    5. *Declarative Drift Reconciliation:* Imperative replica scaling detected and reconciled back to Git desired state in **1.47 seconds**.
* **PostgreSQL Backup & Disaster Recovery (Gate G13):**
  * Implemented an automated backup and restore pipeline with non-destructive disposable target verification.
  * Executed a live DR drill on an isolated target (`forgeops-dr-lab`):
    * `pg_dump` duration: **273 ms** (discrete point-in-time logical backup with SHA-256 checksum manifest; not continuous streaming PITR).
    * `pg_restore` duration: **252 ms** (strict `--exit-on-error` execution into fresh disposable target).
    * End-to-end API service recovery RTO: **89.29 seconds** (including disposable DB provisioning, schema restore, API startup, and BCrypt account authentication).
    * Drill backup currency (backup age): **12.00 seconds** (the age of the test snapshot when restored during the rehearsal drill).
  * Fully verified relational integrity across accounts, projects, and BCrypt-authenticated tasks.
* **Platform Security & Secrets Governance (Gate G14):**
  * 10 Kyverno policies auditing 100% of Helm-rendered Pod specifications in CI against Linux capabilities, root execution, host namespaces, and privilege escalation (20/20 test cases passed).
  * SOPS + age dual-recipient encryption (`Primary Operational` + `Recovery Escrow`) with value-only encryption preserving human-readable Kubernetes metadata.
  * Verified authentic SHA-256 release checksum enforcement in GitHub Actions CI, failing closed on binary tampering.
* **Protected Baseline Continuity:**
  * Throughout all load drills, disaster recovery rehearsals, and policy audits, all **5 protected baseline PersistentVolumeClaims remained 100% intact with zero UID mutation or data loss**.

---

## 5. Architectural Integrity & Boundaries

ForgeOps is intentionally designed as an educational, verifiable platform engineering lab:
- **No Cloud Dependencies:** Operates completely offline without AWS, Azure, GCP, or credit card requirements.
- **Zero Hallucinated State:** Every metric, RTO figure, latency percentiles, and policy test in this repository is derived from actual captured command execution logs stored under `docs/evidence/`.
- **Honest Boundary Documentation:** Single-node Kind resource limits, default `kindnet` NetworkPolicy simulation, and client-side CI policy execution are transparently documented in [KNOWN_LIMITATIONS.md](file:///c:/Project/ForgeOps/docs/portfolio/KNOWN_LIMITATIONS.md).
