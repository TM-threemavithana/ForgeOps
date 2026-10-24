# Gate G00: Environment Preflight & Feasibility Report

**Date:** 2026-10-22  
**Status:** Completed with Documented Limitations  
**Audience:** Platform Engineering, DevSecOps & SRE Reviewers  
**Target Profile:** Core Profile (Strict Sequential Execution Mode)

---

## 1. Executive Summary

This report documents the Phase G00 environment discovery, hardware measurement, toolchain inspection, and feasibility analysis conducted for the ForgeOps platform.

The host is an AMD Ryzen 7 5800H machine running Windows 11 Home with WSL2 (Ubuntu 24.04.1 LTS). Key tooling (Git 2.43.0, Make 4.3, Python 3.12.3, Terraform v1.10.4/v1.11.3, Ansible Core 2.17.7, and kubectl v1.34.1) is installed and operational.

### Critical Limitations Identified:
1. **Host Disk Storage Bottleneck:** The host system drive `C:` has **6.62 GB remaining free space** (out of 459.75 GB). The ForgeOps Master Implementation Plan specifies a minimum of ≥40 GB free SSD for the Core profile, ≥60 GB for Extended, and ≥80 GB for Capstone. Storage cleanup must occur prior to container image caching and Kind cluster instantiation in subsequent gates.
2. **Docker Engine Inactive:** Docker Desktop CLI (v29.5.3, API 1.54) is present, but the Docker Desktop daemon / background service is currently stopped (`com.docker.service Stopped`).
3. **RAM Constraints:** Visible host physical memory is 16 GB (15.38 GiB), with ~1.95 GB free at the time of preflight measurement. WSL2 is allocated 7.5 GiB RAM (with 5.1 GiB free inside WSL).

### Governance Decision:
- ForgeOps will operate strictly under the **Core Execution Profile** with sequential service execution.
- Concurrent execution of the Ansible Linux VM alongside a Kind Kubernetes observability cluster is **strictly prohibited** on this machine configuration.
- Phase G00 is rated: **Passed with Documented Limitations**.

---

## 2. Hardware and Operating System Telemetry

### Host Hardware & Windows Environment
| Component | Measured Value | Minimum Required (Core) | Assessment |
|---|---|---|---|
| **OS** | Windows 11 Home Single Language (Build 10.0.26300) | Windows 10/11 64-bit | Compatible |
| **CPU** | AMD Ryzen 7 5800H with Radeon Graphics (8 Cores, 16 Threads) | 4 Cores | Exceeds requirement |
| **Host Total RAM** | 16,132,880 KB (~15.38 GiB) | 8 GB | Compatible |
| **Host Free RAM** | ~1,956,568 KB (~1.86 GiB) | ≥ 4 GB free for lab | Constrained (requires background app closure) |
| **Host Storage (C:)** | **6.62 GB Free** / 459.75 GB Total (98.6% used) | ≥ 40 GB Free | **CRITICAL CONSTRAINT** |
| **Hypervisor** | HypervisorPresent: `True` (WSL2 / Windows Virtualization) | Required for WSL2 | Enabled |

### WSL2 Linux Environment
| Subsystem | Telemetry Output | Notes |
|---|---|---|
| **Distribution** | Ubuntu 24.04.1 LTS (Noble Numbat) | WSL2 Default |
| **Kernel** | `6.18.54.1-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC` | Modern x86_64 LTS WSL2 kernel |
| **WSL RAM** | Total: 7.5 GiB \| Used: 970 MiB \| Free: 5.1 GiB \| Buff/Cache: 1.6 GiB | Allocated from host dynamically |
| **WSL Swap** | 2.0 GiB Total \| 0 B Used | Standard WSL2 swap |
| **WSL Root FS (`/dev/sdd`)**| 1007 GiB Virtual Disk (7.4 GiB Used, 949 GiB Available in ext4) | Bound by host physical drive C: capacity |

---

## 3. Toolchain and Subsystem Inventory

| Tool / CLI | Host (Windows) Version | WSL2 Ubuntu Version | Plan Target | Status / Action |
|---|---|---|---|---|
| **Git** | 2.43.0 (MinGit) | 2.43.0 | Git ≥2.35 | Verified & Compatible |
| **Docker Engine** | 29.5.3 (Client) | 29.5.3 (Client) | Docker 24+ | Daemon Stopped; Start required in G02 |
| **Docker Compose** | Bundled with Docker Desktop | Bundled / Compose plugin | Compose v2.20+ | Verified |
| **GNU Make** | Not in Windows PATH | 4.3 | Make 4.0+ | Verified via WSL (`make doctor` passing) |
| **Java JDK** | - | OpenJDK 11.0.31 | JDK 17 or 21 LTS | **Upgrade required:** Spring Boot 3/4 requires JDK 17/21 |
| **Python** | Python 3.x | 3.12.3 | Python 3.10+ | Verified |
| **Terraform** | v1.11.3 (windows_amd64) | v1.10.4 (linux_amd64) | Terraform ≥1.8.0 | Verified |
| **Ansible** | - | ansible [core 2.17.7] | Ansible Core 2.16+ | Verified |
| **kubectl** | v1.34.1 | v1.34.1 | kubectl 1.28+ | Verified |
| **kind** | Not installed | Not installed | kind ≥0.24.0 | Planned installation in G06 |
| **Helm** | Not installed | Not installed | Helm 3.14+ | Planned installation in G07 |

---

## 4. Virtualization & Ansible Managed Node Strategy

- **Control Node:** WSL2 Ubuntu 24.04 (`ansible-core 2.17.7`).
- **Target Managed Node:** A dedicated local Ubuntu guest VM managed over SSH on loopback / host-only NAT network.
- **Feasibility Assessment:**
  - Nested virtualization / Hyper-V is active (`HypervisorPresent: True`).
  - VirtualBox or Hyper-V guest creation will require ~1 vCPU, 1-2 GB RAM, and ~10-15 GB disk space.
  - Due to the current 6.62 GB disk constraint on host drive `C:`, guest VM provisioning is deferred until drive space is reclaimed.
  - Per Rule 10 in `AGENTS.md`, a Docker-only container simulation will **not** be substituted for a separate VM.

---

## 5. Execution Profile Decision

Based on the 16 GB host RAM and current disk availability:

```
Selected Profile: CORE (Sequential Mode)
-----------------------------------------------------------
Active Workloads:
  - Phase G01: Spring Boot API + Testcontainers
  - Phase G02: API + PostgreSQL via Docker Compose
  - Phase G04: Independent Ansible Lab (Run separately with Compose stopped)
  - Phase G05: Local Terraform Docker Lab (Isolated fixture)
  - Phase G06+: Single-control-plane Kind cluster (Core profile, 1 replica)
Deferred / Staggered:
  - Observability stack (Prometheus/Grafana/Loki/Alloy) run with minimal retention
  - No simultaneous execution of Kind + Observability + Ansible VM
```

---

## 6. Preflight Command Log Evidence

```bash
# Host Architecture
AMD Ryzen 7 5800H with Radeon Graphics (8 Cores, 16 Logical Processors)
Windows 11 Home Single Language, Version 10.0.26300
Total Memory: 16,132,880 KB | Free Physical Memory: 1,956,568 KB
Volume C: Total 459.75 GB, Free 6.62 GB (CRITICAL CONSTRAINT)

# WSL2 Environment
Linux MSI 6.18.54.1-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC x86_64
Ubuntu 24.04.1 LTS (Noble Numbat)
MemTotal: 7.5 GiB | MemFree: 5.1 GiB | Available: 6.5 GiB

# Tool Versions
git version 2.43.0
GNU Make 4.3
Python 3.12.3
ansible [core 2.17.7]
Terraform v1.10.4 (WSL) / v1.11.3 (Host)
kubectl Client Version: v1.34.1
Docker Client: 29.5.3 (Daemon stopped)
```

**Preflight Sign-Off:** G00 Preflight Completed with Documented Limitations.
