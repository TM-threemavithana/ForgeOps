# Project Risk Register — ForgeOps Platform

**Document Version:** 1.0  
**Effective Date:** 2026-10-22  
**Review Cycle:** Formal review at Gates G00, G05, G08, G10, and G13  
**Status:** Baseline Established (Gate G00)

---

## 1. Risk Matrix Summary

| Likelihood \ Impact | Low | Medium | High |
|---|---|---|---|
| **High** | | **R01, R10, R11** | |
| **Medium** | R13 | **R02, R07, R09** | **R03, R04, R05, R06, R08, R12, R14, R15** |
| **Low** | | | |

---

## 2. Detailed Risk Assessment and Mitigation Log

### R01: Workstation Memory Starvation (RAM Exhaustion)
- **Description:** Concurrently running Kind Kubernetes, Argo CD, Prometheus, Grafana, Loki, Alloy, Spring Boot API, PostgreSQL, and an Ansible Ubuntu VM exhausts host memory (16 GB total visible, with ~1.95 GB free at baseline), causing severe swapping, system freezes, or WSL termination.
- **Likelihood:** High | **Impact:** Medium
- **Mitigation:**
  - Formally select the **Core Execution Profile** with strict sequential execution.
  - Ban concurrent execution of the Ansible VM alongside the Kind observability cluster.
  - Enforce explicit container memory requests and limits (`forgetasks-api`: 512Mi limit, `postgres`: 256Mi limit).
- **Status:** Mitigated via ADR-0008; Core profile active.

### R02: Hypervisor Coexistence Conflict (WSL2 vs. Guest VM)
- **Description:** VirtualBox or third-party hypervisors may conflict with Windows Hyper-V platform / WSL2 on Windows 11 Home, preventing guest VM launch for Ansible.
- **Likelihood:** Medium | **Impact:** Medium
- **Mitigation:**
  - Validate hypervisor coexistence during G00 (`HypervisorPresent: True`).
  - Use Hyper-V or WSL-compatible hypervisor backend.
  - If hypervisor coexistence fails, execute the Ansible VM lab separately on host reboot or documented standalone profile; never substitute a Docker container for the VM.
- **Status:** Monitored; VM deferred until G04.

### R03: Untrusted CI Supply Chain Privilege Escalation
- **Description:** Workflows triggered by pull requests from external forks could execute untrusted code with elevated repository or registry write permissions.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Set default workflow permissions to `permissions: read-all`.
  - Strictly isolate container image publishing to trusted `main` branch merges in `release.yml`.
  - Never provide `packages: write` tokens to PR check jobs.
- **Status:** Mitigated via ADR-0009; enforced in CI workflow design.

### R04: Catastrophic Database Loss via Kind Cluster Reset
- **Description:** Executing `kind delete cluster` or recreating cluster nodes destroys all internal PersistentVolumeClaims and local container storage, permanently erasing database state.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Implement automated host-side backups via `pg_dump` (`make backup-db`), storing compressed dumps with SHA256 checksums in `~/.config/forgeops/backups/` outside Docker volumes.
  - Require explicit confirmation (`CONFIRM=yes`) for destructive cluster deletion commands.
  - Mandate backup integrity verification (`make verify-backup`) prior to any cluster reset.
- **Status:** Mitigated via ADR-0005; runbook defined.

### R05: Credential or Terraform State Leaks to Public Git
- **Description:** Accidental commit of `.env.local`, raw private keys, database passwords, or `terraform.tfstate` files (which store plaintext resource attributes) to public GitHub remotes.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Comprehensive `.gitignore` strictly excluding `*.tfstate*`, `.env*`, `*.key`, `*kubeconfig*`, and `secrets/`.
  - Out-of-band secret generation in `~/.config/forgeops/secrets/`.
  - Automated Gitleaks scanning in pre-commit hooks and GitHub Actions workflows.
- **Status:** Mitigated via ADR-0006; `.gitignore` created in G00.

### R06: Resource Ownership Collision (Terraform vs. Argo CD)
- **Description:** Terraform and Argo CD attempting to manage the same Kubernetes resources (e.g., Deployments or Namespaces), causing endless reconciliation loops and configuration drift.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Enforce the Strict Sole Owner Contract (ADR-0003).
  - Terraform manages *only* the initial Argo CD platform bootstrap release.
  - Argo CD has exclusive ownership of all application and observability workloads.
- **Status:** Mitigated via ADR-0003.

### R07: NetworkPolicy Security Illusion under Default Kindnet
- **Description:** Authoring Kubernetes `NetworkPolicy` manifests in default Kind and claiming network isolation when `kindnet` actually fails to enforce them.
- **Likelihood:** High | **Impact:** Medium (Reputational & Security)
- **Mitigation:**
  - Document that default Kindnet does not enforce NetworkPolicies.
  - Create a dedicated, clean Cilium eBPF Kind profile (`platform/kind/cilium.yaml`) with default CNI disabled for Phase G11 and Capstone negative security tests.
- **Status:** Mitigated via ADR-0011.

### R08: Unrealistic SLA and High Availability Claims
- **Description:** Claiming 99.99% multi-region enterprise availability or zero-downtime production SLAs for a local single-node Kind cluster running on a laptop.
- **Likelihood:** Medium | **Impact:** High (Reputational)
- **Mitigation:**
  - Formally document single-host failure domain boundaries in README and SRS.
  - Frame availability goals as **Lab Learning Objectives** tested under controlled k6 load rather than production SLA guarantees.
- **Status:** Mitigated via ADR-0001, ADR-0002, and ADR-0012.

### R09: Dependency Incompatibility and Stale Toolchains
- **Description:** Blindly using `:latest` tags or outdated tutorial configurations, leading to broken builds when dependencies deprecate APIs (e.g., Promtail sunset).
- **Likelihood:** Medium | **Impact:** Medium
- **Mitigation:**
  - Maintain an exact, verified Compatibility Matrix (`docs/compatibility-matrix.md`) cross-referenced against current official documentation.
  - Pin all image digests, Helm chart versions, Maven dependencies, and GitHub Actions.
  - Promtail strictly banned and replaced with Grafana Alloy.
- **Status:** Mitigated via Compatibility Matrix in G00.

### R10: Project Scope Creep Across 20+ DevOps Tools
- **Description:** Attempting to implement advanced tools (Jenkins, Tempo, Cilium, SOPS, Kyverno) before the core delivery loop (G01–G08) is verified and stable.
- **Likelihood:** High | **Impact:** Medium
- **Mitigation:**
  - Strictly enforce the Review-Driven Gate Workflow (AGENTS.md): exactly one gate (G00–G15) per reviewed change.
  - Segregate advanced platform tools into the optional Capstone gate (G14).
- **Status:** Enforced by Gate Operating Rules.

### R11: Host Storage Exhaustion (CRITICAL CURRENT BOTTLENECK)
- **Description:** Docker container image layers, Kind node root filesystems, Maven build caches, and system logs rapidly consume disk space. **The host system drive `C:` currently has only 6.62 GB free space remaining**, well below the 40 GB Core profile recommendation.
- **Likelihood:** High | **Impact:** High (Host System Failure)
- **Mitigation:**
  - Flagged as a Critical Blocker in G00 Preflight Report.
  - Mandatory operator action required: free at least 30–40 GB on drive `C:` before launching Docker containers in G02/G06.
  - Configure strict log retention caps (24 hours / 500 MB) in Loki and Docker daemon.
  - Prohibit arbitrary `docker system prune -a` to prevent destroying cached images; use targeted volume and builder prune with confirmation.
- **Status:** **ACTIVE CRITICAL LIMITATION — Logged in G00 Evidence**.

### R12: Accidental Public Network Exposure of Dashboards & APIs
- **Description:** Exposing Grafana, Argo CD, or PostgreSQL on `0.0.0.0`, making internal credentials and cluster controls accessible to untrusted devices on the local Wi-Fi network.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Bind all ports strictly to `127.0.0.1` (loopback).
  - Use `kubectl port-forward --address 127.0.0.1` for all cluster services.
  - Verify external port denial via network scans.
- **Status:** Mitigated via ADR-0001 and Network Architecture (ADR-0004).

### R13: Free Tier & GitHub Hosted Runner Limit Changes
- **Description:** GitHub changing free public repository Action runner minutes or GHCR storage policies.
- **Likelihood:** Medium | **Impact:** Low
- **Mitigation:**
  - Maintain a fully offline local build and deployment path (`make ci` + `docker build` + `kind load docker-image`).
  - Monitor GitHub billing documentation.
- **Status:** Mitigated; local fallback path planned in G03.

### R14: Database Schema Drift During Application Rollback
- **Description:** Application rollback succeeds via Git revert, but the database schema was modified by a non-backward-compatible migration, causing the rolled-back application to fail on SQL queries.
- **Likelihood:** Medium | **Impact:** High
- **Mitigation:**
  - Strictly mandate the Expand/Contract migration pattern for all Flyway scripts.
  - Ensure schema changes are backward-compatible with the immediately preceding application version.
  - Test rollback drill DR-02 against migrated database schemas.
- **Status:** Mitigated via ADR-0010.

### R15: Docker Desktop Engine Inactive / Stopped
- **Description:** Docker Desktop client is installed (v29.5.3), but the Docker daemon / service is currently stopped (`com.docker.service Stopped`), preventing container execution.
- **Likelihood:** Medium | **Impact:** High (Blocks G01 Testcontainers / G02 Compose)
- **Mitigation:**
  - Identified and documented in G00 Preflight Report.
  - Start Docker Desktop engine prior to running Phase G01 integration tests and Phase G02 Docker Compose workloads.
- **Status:** Documented in G00 Acceptance; action scheduled for G01/G02.
