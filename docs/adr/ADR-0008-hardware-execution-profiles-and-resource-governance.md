# ADR-0008: Hardware Execution Profiles and Resource Governance

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
Deploying enterprise DevOps platforms locally on personal laptops often causes system freezes, Docker crashes, and out-of-memory (OOM) killing when all components (Kind cluster, Prometheus, Grafana, Loki, Alloy, Argo CD, Spring Boot API, PostgreSQL, and a separate Ubuntu VM for Ansible) are launched concurrently.

Preflight measurements on the current host reveal:
- Physical RAM: 16 GB (with only ~1.95 GB free on Windows at baseline).
- WSL2 RAM allocation: 7.5 GB max.
- Available Host Disk (`C:`): **6.62 GB free SSD** (critical bottleneck).

Running all components simultaneously is technically impossible and would trigger host system crashes.

## Options Considered
1. **Unconstrained Concurrent Launch:** Attempt to run everything simultaneously. Rejected; guaranteed to crash Docker and WSL due to memory and disk exhaustion.
2. **Cloud Offloading:** Offload heavy components to AWS/GCP. Rejected; violates the zero-cloud-cost hard boundary.
3. **Structured Tiered Profiles (Core / Extended / Capstone) with Sequential Execution:** Partition the architecture into discrete profiles and enforce sequential runtime isolation.

## Decision
Adopt **Tiered Hardware Profiles** and select the **CORE PROFILE (Sequential Execution Mode)**:

### 1. Profile Definitions:
- **Core Profile (Target for Current Host):**
  - Designed for 8–16 GB RAM and constrained SSD storage.
  - Workloads run sequentially:
    - Docker Compose API + DB for local development (Phase G01–G02).
    - Ansible lab VM runs as a standalone exercise with Kind and Compose stopped (Phase G04).
    - Kind cluster runs single-control-plane with 1 API replica, 1 PostgreSQL instance, and Argo CD (Phase G06–G08).
    - Observability runs with strictly capped 24-hour retention.
- **Extended Profile (Future):**
  - Requires 16 GB+ RAM and ≥60 GB free SSD. Enables control-plane + worker Kind cluster and concurrent Prometheus metrics.
- **Capstone Profile (Future):**
  - Requires 24–32 GB RAM and ≥80 GB free SSD. Enables full multi-node Kind cluster, Tempo tracing, Cilium eBPF, and concurrent VM.

### 2. Immediate Resource Protection Rules:
- Before running Docker or Kind workloads, the operator must free at least 30–40 GB on drive `C:`.
- The Ansible Ubuntu VM will **never** be run concurrently with the Kind observability cluster.
- Container memory limits are strictly enforced in manifests (`forgetasks-api`: requests 256Mi / limits 512Mi; `postgres`: requests 128Mi / limits 256Mi).

## Consequences & Trade-offs
### Positive:
- **Host Stability:** Prevents system lockups, kernel panics, and WSL crash loops.
- **Realistic Engineering:** Emphasizes resource stewardship, sizing calculations, and capacity planning.

### Negative / Limitations:
- The operator must explicitly stop one subsystem before starting another (e.g., `make compose-down` before `make cluster-create`).
- Demonstrating Ansible VM management and Kind observability simultaneously is not supported on this hardware configuration.

## Verification Tests
- Memory consumption monitored via `free -h` and `docker stats`.
- Total memory allocated to active Docker containers remains under 4.0 GiB in the Core profile.
- Disk usage monitored via `df -h` to ensure operations abort if available space drops below 2 GB.

## Reconsideration Triggers
- Upgrading host physical RAM to 32 GB or adding an external SSD with ≥100 GB dedicated space.
