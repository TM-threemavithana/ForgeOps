# ForgeOps Roadmap Reconciliation & Security Baseline

**Date:** 2026-10-28  
**Scope:** Architecture alignment across Gates G08–G12, security posture baseline, and verified controls  
**Author:** Lead SRE & Platform Engineer  

---

## 1. Executive Summary & Gate Sequencing Alignment

In the initial draft of the [ForgeOps Master Implementation Plan](FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md), the gate sequencing designated Gate G11 as *Security, RBAC and supply chain*, while placing *OpenTelemetry and Tempo distributed tracing* under Gate G14 as an optional advanced track.

During real-world platform implementation, an architectural decision was made to execute **Distributed Tracing** under **Gate G11** (`feat/g11-opentelemetry-tracing` [PR #40](https://github.com/TM-threemavithana/ForgeOps/pull/40) and `feat/g11-tempo-alloy-tracing` [PR #41](https://github.com/TM-threemavithana/ForgeOps/pull/41)).

### Technical Rationale for Gate G11 Tracing Prior to Gate G12 SRE
1. **Observability Triad Unification:** Modern Site Reliability Engineering requires the complete observability triad—**Metrics** (G09 Prometheus), **Logs** (G10 Loki/Alloy), and **Traces** (G11 Tempo/OTel)—to observe system health under load and reconstruct failure timelines.
2. **High-Fidelity SRE Telemetry:** Gate G12 load and chaos testing requires distributed trace context (`traceparent`, `X-Request-ID`) to distinguish whether latency degradation under concurrency originates in the Spring Boot dispatcher servlet, Hibernate query execution, HikariCP pool queuing, or container cgroup throttling.
3. **Trace-to-Logs Incident Triage:** Establishing the Grafana `tracesToLogsV2` navigation bridge in G11 provides the foundation for the SRE incident runbooks developed in G12.

Existing gate evidence directories (`docs/evidence/G00` through `docs/evidence/G11`) remain authoritative and unrenumbered.

---

## 2. Comprehensive Security Baseline (G01–G11)

Security controls in ForgeOps have been implemented progressively across all previous gates. The matrix below documents every security requirement, its current verification status, and its tangible evidence.

### Security Controls Matrix

| Domain | Control / Requirement | Status | Verification Mechanism & Evidence |
|:---|:---|:---|:---|
| **Supply Chain** | Static Secret Leak Detection | **ENFORCED** | Gitleaks scanning in CI workflow (`.github/workflows/ci.yml`). Verified with canary leak tests in G03. |
| **Supply Chain** | Container Vulnerability Scanning | **ENFORCED** | Trivy security scanner blocks CI and release publish on any CRITICAL or HIGH CVEs. Passed in G03, G08, and G11 (`publish.yml`). |
| **Supply Chain** | Software Bill of Materials (SBOM) | **ENFORCED** | CycloneDX SBOM generated and uploaded as release artifact for every published container image (`publish.yml`). |
| **Supply Chain** | SLSA Build Provenance | **ENFORCED** | SLSA v2 build provenance attested and signed via `actions/attest-build-provenance` to GHCR registry. |
| **Supply Chain** | Immutable Deployment References | **ENFORCED** | GitOps manifests (`values-rehearsal.yaml`) pin exact container image digests (`@sha256:...`), eliminating mutable tag drift. |
| **Container Runtime** | Non-Root Container Execution | **ENFORCED** | Dedicated user `appuser:appgroup` (UID `10001:10001`) enforced in multi-stage Dockerfile and verified in G02/G06. |
| **Container Runtime** | Linux Capability Restriction | **ENFORCED** | `cap_drop: [ALL]` in Docker Compose; `allowPrivilegeEscalation: false` and minimal capabilities in Helm chart. |
| **Container Runtime** | Seccomp Profile Enforcement | **ENFORCED** | `seccompProfile: { type: RuntimeDefault }` configured on all application and database pod specifications. |
| **Container Runtime** | Read-Only Root Filesystem | **LIMITATION** | *Unverified.* Not enabled due to Spring Boot / Tomcat temp write requirements (`/tmp`, workdir). Reserved for future emptyDir mount refactoring. |
| **Kubernetes RBAC** | Dedicated Service Accounts | **ENFORCED** | Isolated ServiceAccounts provisioned for API, DB, Alloy, and Tempo (`serviceAccountName` explicitly bound). |
| **Kubernetes RBAC** | Least-Privilege Scoped RBAC | **ENFORCED** | Alloy ServiceAccount granted read-only pod access strictly in `forgeops-gitops-rehearsal`. Negative tests confirmed Alloy is denied dev pods and secrets. |
| **Kubernetes RBAC** | Zero Cluster Node Permissions | **ENFORCED** | Tempo ServiceAccount verified with 0 cluster-scoped permissions (tested via `kubectl auth can-i get nodes`). |
| **Secrets Management**| Out-of-Band Secret Injection | **ENFORCED** | Database credentials injected via Kubernetes Secret (`forgetasks-rehearsal-db-secret`). Zero plaintext secrets in Git, Helm values, or rendered manifests. |
| **Network Security** | Loopback Host Binding | **ENFORCED** | All local ports (Kind node, Prometheus, Grafana, Loki, Tempo, API) bind exclusively to `127.0.0.1`. No external network interfaces exposed. |
| **Network Security** | In-Cluster NetworkPolicy Enforcement | **LIMITATION** | *Not Enforced.* Cluster runs Kind default `kindnet` CNI, which does not enforce NetworkPolicy packet filtering. Cilium installation is deferred to protect host resources. |
| **Application Sec** | Tenant Data Isolation | **ENFORCED** | Repository-level tenant query filtering. Cross-tenant access attempts return HTTP 404 to prevent resource enumeration. |
| **Application Sec** | Lost Update Prevention (RFC 9110) | **ENFORCED** | Optimistic concurrency using `ETag` and `If-Match` headers. Missing/stale preconditions return HTTP 428 / 412. |
| **Application Sec** | Telemetry Credential Redaction | **ENFORCED** | Passwords, tokens, cookies, and Authorization headers are excluded from both Loki logs and Tempo trace span attributes (verified in G10 and G11). |

---

## 3. Explicit Acknowledged Security Limitations

To maintain strict truthfulness boundaries:
1. **NetworkPolicy Isolation:** NetworkPolicy YAML manifests can be rendered by Kubernetes, but **cannot be claimed as enforced** in the current environment because the default `kindnet` CNI lacks eBPF/iptables policy filtering. In accordance with platform operating rules, Cilium has not been installed to avoid exceeding workstation memory and CPU profiles.
2. **Policy-as-Code Admission Webhooks:** Dynamic admission controllers (e.g., Kyverno or OPA Gatekeeper) are not deployed on the single-node local cluster.
3. **Mutual TLS (mTLS):** Intra-cluster pod-to-pod communication uses standard Kubernetes Service DNS without service-mesh mTLS encryption. Loopback binding on the host mitigates external sniffing risk.

---

## 4. Current Platform Roadmap Status

| Gate | Domain | Status | Verification Summary |
|:---|:---|:---|:---|
| **G00** | Preflight, Hardware Feasibility & Architecture Baseline | **PASSED** | Core execution profile validated on Windows/WSL2 Docker host. |
| **G01** | ForgeTasks API Backend & PostgreSQL Schema Correctness | **PASSED** | Multi-tenant REST API with Flyway migrations and Testcontainers. |
| **G02** | Multi-Stage Containerization & Docker Compose Stack | **PASSED** | Non-root runtime, out-of-band secret injection, loopback binding. |
| **G03** | CI Pipelines, Trust Boundaries & GHCR Publishing | **PASSED** | Gitleaks, Trivy, SBOM, SLSA provenance, and release guard. |
| **G04** | Ansible Linux Host Configuration Management | **PASSED** | Idempotent Ubuntu guest provisioning over SSH. |
| **G05** | Terraform Local Docker Lab Fixture | **PASSED** | Declarative Docker fixture lifecycle and drift management. |
| **G06** | Local Kind Kubernetes Cluster & CNI | **PASSED** | Single-node Kind cluster, namespace isolation, storage provisioner. |
| **G07** | Helm Reusable Application Chart | **PASSED** | Parameterized chart with dev/rehearsal profiles and lint tests. |
| **G08** | Platform Bootstrap & Argo CD GitOps | **PASSED** | Declarative GitOps, manual promotion, immutable digest sync. |
| **G09** | Prometheus Metrics & Alertmanager Alerting Rules | **PASSED** | JVM/HTTP metrics, custom dashboards, alert firing/resolution. |
| **G10** | Loki & Alloy Centralized Logging | **PASSED** | Pod log ingestion, ECS JSON format, request-ID correlation. |
| **G11** | Distributed Tracing with Grafana Tempo & OpenTelemetry | **PASSED** | OTLP tracing, W3C traceparent propagation, trace-to-logs LogQL. |
| **G12** | SRE Reliability Engineering, k6 Load Testing & Chaos Drills | **IN PROGRESS** | k6 performance suites, disposable chaos lab, SLIs/SLOs, runbooks. |
| **G13** | Database Disaster Recovery, Backup & Restoration Drill | *Planned* | Scheduled following Gate G12. |
| **G14** | Complete System Teardown & Reconstruction Runbook | *Planned* | Scheduled following Gate G13. |
| **G15** | Final Project Showcase, Architectural Portfolio & Video | *Planned* | Final gate. |
