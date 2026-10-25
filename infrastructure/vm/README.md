# ForgeOps Virtual Machine Infrastructure — Ansible Managed Node

- **Document Version:** 1.1
- **Effective Gate:** G04 Phase 1
- **Target Profile:** Core Profile (Local-First, Zero Cloud Dependency)
- **Virtualization Backend:** Oracle VM VirtualBox 7.2.8 (Windows 11 Host)

---

## 1. Overview & Architectural Role

The `infrastructure/vm` directory contains the topology specification, network architecture, and operational runbooks for the dedicated Linux guest virtual machine managed by Ansible in Gate G04.

Per **Rule 10** in `AGENTS.md` and **REQ-P-05.3** in `docs/requirements/SRS.md`, the managed node must be an **actual independent Linux virtual machine** controlled via SSH. A Docker container simulation or a secondary WSL2 distribution is explicitly prohibited.

Per **ADR-0003** (Strict Resource Ownership), Ansible playbooks own the guest operating system, packages, user configuration, SSH hardening, UFW firewall, and Nginx web services.

---

## 2. Virtual Machine Technical Specifications

| Parameter | Specification | Selection Rationale |
|---|---|---|
| **VM Name** | `forgeops-ansible-lab` | Unique, standardized lab identifier |
| **Guest OS** | Ubuntu Server 24.04.5 LTS (Noble Numbat 64-bit) | Modern LTS release matching controller; systemd 255, OpenSSH 9.6p1, Python 3.12 |
| **VirtualBox Version** | 7.2.8r173730 | Installed at `C:\Program Files\Oracle\VirtualBox` |
| **VM Base Directory** | `C:\Users\User\VirtualBox VMs\forgeops-ansible-lab` | Standard VirtualBox default location |
| **vCPU Allocation** | 2 vCPUs | Responsive package compilation and background service execution |
| **RAM Allocation** | 2048 MB (2.0 GiB) | Fits within 15.4 GB host memory budget without causing host memory starvation |
| **Storage (VDI)** | 25.0 GB Dynamic VDI (`forgeops-ansible-lab.vdi`) | Sufficient for OS base (~4 GB) + packages; allocates on demand from 52.1 GB free host space |
| **Storage Controller** | SATA (AHCI) | Optimal I/O performance under VirtualBox |
| **Network Adapter 1** | **NAT (VirtualBox NAT Engine)** | Outbound internet for apt updates; strictly controlled inbound port forwarding |
| **Primary Port Forwarding** | Name: `guestssh`<br>Protocol: `TCP`<br>Host IP: `192.168.96.1` (Windows WSL gateway)<br>Host Port: `2222`<br>Guest IP: *(blank / dynamic)*<br>Guest Port: `22` | **Preserved VirtualBox SSH forwarding rule**: `guestssh,tcp,192.168.96.1,2222,,22` per Rule 9. Leaves Guest IP blank so VirtualBox matches dynamic DHCP NAT IP (e.g. 10.0.2.x). |
| **Secondary Port Forwarding** | HTTP (8088 -> 80) | **Deferred** until Nginx role deployment and verification |
| **User Account** | `ops` (installer-created) | Standard non-root operator; UID/GID assigned by installer (typically 1000) preserved |
| **Graphics / Audio** | VMSVGA (16 MB VRAM) / Audio Disabled | Headless server profile; saves host memory |

---

## 3. Host Safety & Environmental Boundaries

1. **Preserve Existing VMs:** Three historical Kali Linux VMs registered on the host (`{3ee94966...}`, `{b0d6a445...}`, `{50ee7ec3...}`) are inaccessible due to missing `.vbox` configuration paths. **Do not modify, unregister, or delete these VMs.**
2. **Dynamic Network Values:** Do not assume WSL default gateway `192.168.96.1` or guest NAT IP `10.0.2.15` will always be static. Treat these as observed values; dynamically discover the host IP and verify reachability before setting local inventory overrides.
3. **Host-Only Adapter Isolation:** The existing VirtualBox Host-Only Ethernet Adapter (`Ethernet 7`) has an unconfigured APIPA address (`169.254.249.5`). It is **not** used in Phase 1 to prevent routing anomalies.
4. **Core Profile Sequentiality:** Never run the Ansible VM concurrently with a Kind Kubernetes cluster or heavy Docker Compose stacks. Total available host RAM is ~15.4 GB. Sequential execution ensures zero host swapping.
5. **Zero Cloud Expense:** No AWS EC2, Azure VM, GCP Compute Engine, or VPS resources are required or permitted.
