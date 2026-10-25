# Gate G04 Readiness Report — Ansible Architecture, Repository Preparation & Security Preflight

- **Date:** 2026-10-25
- **Evaluator:** Tharuka Madhuwantha Threemavithana (`157876462+TM-threemavithana@users.noreply.github.com`)
- **Role:** Principal DevOps Engineer, Linux Infrastructure Engineer & Ansible Architect
- **Gate:** G04 — Ansible Linux Host Configuration Management (Phase 1: Architecture & Security Preflight)
- **Status:** PASSED — PENDING PR REVIEW AND MERGE
- **Repository Branch:** `g04-ansible-linux-guest`
- **Latest Master Commit:** `9a77220abdb9e9012c4b169f6522e911c03efffc` (PR #14 merged)
- **Execution Profile:** Core Profile (Local-First, Strict Sequential Execution)

---

## 1. Executive Summary

Gate G04 establishes automated, idempotent configuration management for a dedicated local Linux host using Ansible Core 2.17.7. In accordance with **Rule 10** in `AGENTS.md` and **REQ-P-05.3**, the target managed node is an actual independent Ubuntu Server 24.04.5 LTS virtual machine running under Oracle VM VirtualBox 7.2.8, strictly rejecting any containerized simulation.

The actual managed guest virtual machine (`forgeops-ansible-lab`) has been successfully instantiated, provisioned, and verified:
- **Guest VM Verified:** Ubuntu Server 24.04.5 LTS running in VirtualBox 7.2.8 with 2 vCPUs, 2 GB RAM, and 25 GB dynamic VDI.
- **SSH Connectivity Verified:** OpenSSH server running on guest; reachable via single restricted NAT port forwarding (`guestssh,tcp,192.168.96.1,2222,,22`).
- **Cryptographic Host Verification:** Guest SSH host key fingerprint is verified and permanently stored in the controller's trusted `~/.ssh/known_hosts`. Host key checking is strictly enabled (`host_key_checking = True` in `ansible.cfg`).
- **Key-Based Authentication:** Dedicated keypair `~/.ssh/forgeops_lab_ed25519` verified with password authentication disabled on client.
- **Sudo Privilege:** Privilege escalation verified using `--ask-become-pass`.
- **Ansible Connectivity:** `ansible -m ping` succeeds with `"ping": "pong"`.
- **Baseline Snapshot:** VirtualBox snapshot `clean-installed-baseline` confirmed prior to configuration management.

All offline security preflight hardening has been completed:
1. **Host Verification Enforced:** Removed all bypass options (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`) from `ansible.cfg`, inventory templates, and runbooks.
2. **Cloud-Init Precedence Handled:** Hardening drop-in renamed to `00-forgeops-hardening.conf` to ensure precedence over Ubuntu cloud-init (`50-cloud-init.conf`). Obsolete `Protocol 2` removed; existing host keys and Ed25519 authentication preserved.
3. **Pre-Activation Validation:** Candidate sshd configuration is validated with `/usr/sbin/sshd -t` before activation, and verified with `sshd -T`.
4. **Anti-Lockout Safety Checks:** Assertions prevent disabling password authentication unless the operator's public key is present and verified on the guest.
5. **Firewall Task Reordering:** UFW firewall tasks reordered to explicitly open SSH port 22 and HTTP port 80 *before* enforcing default incoming deny.
6. **Zero Secrets in Git:** Dedicated private key and `hosts.local.yml` remain untracked and strictly outside Git.

**Execution Boundary:** All planned runtime acceptance tests (A-401.1–A-401.5 convergence, A-401.6 external firewall port drop, A-402.1–A-402.2 idempotence & audit, and DR-09 drift recovery) have been executed and passed on the live Ubuntu Server 24.04.5 LTS guest. In accordance with `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` (§G04 acceptance: "firewall blocks designated test port without blocking SSH"), all mandatory acceptance criteria are fully evidenced. G04 technical acceptance is **PASSED — PENDING PR REVIEW AND MERGE**. Final gate closure is subject to GitHub PR review and merge approval.

---

## 2. Verified Host & Controller Environment Baseline

### 2.1 Windows Host Telemetry
- **OS:** Windows 11 Home Single Language, Version 24H2 (Build 10.0.26300).
- **CPU:** AMD Ryzen 7 5800H (8 Cores, 16 Threads).
- **Physical RAM:** 16,132,880 KB (~15.38 GiB total; ample headroom under sequential Core profile).
- **Windows C: Drive Storage:** ~52.1 GB free space.
- **Hypervisor:** VirtualBox 7.2.8r173730 installed at `C:\Program Files\Oracle\VirtualBox`.
- **Existing Registered VMs:** Three historical Kali Linux VMs registered but inaccessible (`{3ee94966...}`, `{b0d6a445...}`, `{50ee7ec3...}`) due to missing `.vbox` configuration paths. Preserved untouched per safety boundaries.
- **Active Lab VM:** `forgeops-ansible-lab` running Ubuntu Server 24.04.5 LTS.
- **Host Baseline Snapshot:** `clean-installed-baseline` taken and confirmed.

### 2.2 WSL2 Controller Telemetry
- **Linux Distribution:** Ubuntu 24.04.1 LTS (Noble Numbat).
- **Kernel:** Linux `6.18.54.1-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC`.
- **Ansible Core:** `ansible [core 2.17.7]` installed at `/usr/bin/ansible`.
- **Python:** `Python 3.12.3` at `/usr/bin/python3`.
- **OpenSSH Client:** `OpenSSH_9.6p1 Ubuntu-3ubuntu13.20, OpenSSL 3.0.13 30 Jan 2024`.
- **Ansible Collections:** `ansible.posix` (1.6.2) and `community.general` (9.5.2) installed.
- **SSH Trusted Known Hosts:** Host fingerprint stored in `/home/tharuka/.ssh/known_hosts`.
- **Ansible Ping Status:** Permanent connectivity verified (`ansible -m ping` -> `pong`).

---

## 3. Architecture & Trust Boundaries

```
+-----------------------------------------------------------------------------------+
| WINDOWS 11 HOST WORKSTATION (VirtualBox 7.2.8 at C:\Program Files\Oracle\VirtualBox)|
|                                                                                   |
|  +-------------------------------------+   +------------------------------------+ |
|  | WSL2 Linux Controller (Ubuntu 24)   |   | Oracle VM VirtualBox VM            | |
|  | - ansible-core 2.17.7               |   | - VM Name: forgeops-ansible-lab    | |
|  | - host_key_checking = True          |   | - OS: Ubuntu Server 24.04.5 LTS    | |
|  | - known_hosts strictly enforced     |   | - 2 vCPUs, 2048 MB RAM, 25 GB VDI  | |
|  | - Key: ~/.ssh/forgeops_lab_ed25519  |   | - User: ops (installer UID 1000)   | |
|  |   (outside Git repository)          |   | - Baseline Snapshot: confirmed     | |
|  |                                     |   | - Guest IP: Dynamic NAT DHCP       | |
|  |                                     |   |                                    | |
|  | Transport: Verified SSH (Port 2222) |   | Single Restricted Forwarding Rule: | |
|  +------------------+------------------+   | guestssh,tcp,192.168.96.1,2222,,22 | |
|                     |                      +-----------------+------------------+ |
|                     +----------------------------------------+                    |
|                                                                                   |
|  [SECURITY BOUNDARY] Cryptographic host-key verification active against           |
|  ~/.ssh/known_hosts. Zero wildcard 0.0.0.0 bindings. No external Wi-Fi / LAN      |
|  exposure. Private keys and overrides kept outside Git.                           |
+-----------------------------------------------------------------------------------+
```

### 3.1 Trust Boundaries & Resource Ownership
1. **Sole Owner Contract (ADR-0003):** Ansible playbooks own the guest operating system packages, user accounts, SSH configuration, UFW firewall, and Nginx. Terraform and Docker CLI do not touch the virtual machine.
2. **Sequential Core Profile (ADR-0008):** Due to 15.4 GB host memory, the Ansible VM executes sequentially. Running Kind Kubernetes simultaneously with the Ansible VM is strictly prohibited.
3. **No Container Substitution (REQ-P-05.3):** Real Ubuntu Server guest verified. Container simulations strictly rejected.
4. **Strict Host Verification (Rule 9):** SSH host-key bypasses are permanently removed. All sessions verify the guest's fingerprint against `~/.ssh/known_hosts`.

---

## 4. Planned Ansible Component Inventory

```
infrastructure/
├── ansible/
│   ├── ansible.cfg                          # host_key_checking=True, trusted known_hosts
│   ├── requirements.yml                     # Pinned collections: ansible.posix 1.6.2, community.general 9.5.2
│   ├── inventories/
│   │   └── lab/
│   │       ├── hosts.yml                    # Tracked baseline inventory (host-key verified)
│   │       ├── hosts.example.yml            # Local override example with dynamic host discovery
│   │       └── group_vars/
│   │           ├── all.yml                  # Global UTC timezone, python3, package lists
│   │           ├── managed_lab.yml          # Ops user, public key file, SSH & firewall vars
│   │           └── webservers.yml           # Nginx port, docroot, server name vars
│   ├── playbooks/
│   │   ├── site.yml                         # Main convergence playbook (5 roles in anti-lockout order)
│   │   └── verify.yml                       # Non-mutating audit playbook (audits 00- drop-in & sshd -T)
│   └── roles/
│       ├── baseline/                        # UTC timezone, apt cache, core packages
│       ├── users/                           # Safely manages installer ops account (preserves UID)
│       ├── ssh-hardening/                   # 00- drop-in, candidate validation, sshd -T checks
│       ├── firewall/                        # Anti-lockout ordering: allow 22 & 80 before deny
│       └── nginx/                           # Nginx install, site config, /health
└── vm/
    ├── README.md                            # Architecture & hardware specifications
    └── bootstrap-notes.md                   # Installation, key setup, and recovery runbook
```

---

## 5. Security Controls, Preflight Hardening & Anti-Lockout Strategy

### 5.1 Enforced SSH Host Verification
- `host_key_checking = True` in `infrastructure/ansible/ansible.cfg`.
- Removed `UserKnownHostsFile=/dev/null` and `StrictHostKeyChecking=accept-new` from `ssh_args`.
- Removed `ansible_ssh_common_args` bypasses from `hosts.yml`, `hosts.example.yml`, and `bootstrap-notes.md`.
- All connections are validated against the trusted `/home/tharuka/.ssh/known_hosts`.

### 5.2 OpenSSH Hardening Drop-in (`00-forgeops-hardening.conf`)
- **Cloud-Init Precedence:** In Ubuntu 24.04, `/etc/ssh/sshd_config.d/*.conf` is read lexicographically. Cloud-init writes `50-cloud-init.conf`. The hardening file is deployed as `00-forgeops-hardening.conf` so its directives take precedence.
- **Legacy Cleanup:** Any older `99-forgeops-hardening.conf` is explicitly removed by Ansible.
- **Obsolete Directives Removed:** `Protocol 2` removed.
- **Candidate Validation:** Template is staged to `.00-forgeops-hardening.conf.candidate` and tested with `/usr/sbin/sshd -t` prior to activation.
- **Effective Configuration Inspection:** Inspects effective settings via `sshd -T` and verifies that `passwordauthentication no`, `permitrootlogin no`, and `pubkeyauthentication yes` are reported.
- **Anti-Lockout Assertion:** Explicit task prevents disabling password authentication unless `authorized_keys` exists and is non-empty on the guest.

### 5.3 Account Management Safety (User `ops`)
- **Preserve Installer UID:** In Ubuntu Server installations, user `ops` is created with UID 1000 and GID 1000. The `users` role safely manages group memberships (`sudo`), shell (`/bin/bash`), and authorized keys without asserting a rigid `uid: 1001`.
- **Public Key Resolution:** Automatically resolves `/home/tharuka/.ssh/forgeops_lab_ed25519.pub` via controller `lookup('ansible.builtin.file', ...)` while preserving existing keys in `authorized_keys`.

### 5.4 UFW Anti-Lockout Ordering
- Firewall tasks reordered: SSH port 22 and HTTP port 80 are explicitly created and registered in UFW *before* setting default incoming policy to deny and *before* enabling UFW.

---

## 6. Acceptance Test Status Matrix (A-401, A-402 & DR-09)

> **Environment:** Controller — WSL2 Ubuntu, Ansible Core 2.17.7.
> Managed guest — Ubuntu Server 24.04.5 LTS, VirtualBox VM `forgeops-ansible-lab`.
> Ansible inventory identifier: `forgeops-node-01`. Note: `forgeops-node-01` is the Ansible inventory label;
> the actual Ubuntu OS hostname was set during installation and was not independently re-verified during convergence.
> SSH private key resides outside Git. `hosts.local.yml` is git-ignored.

| Test ID | Test Scenario | Execution Command | Target Outcome | Result |
|---|---|---|---|---|
| **A-401.1** | Controller Scaffolding & Syntax | `make ansible-check` | 8 checks PASS; exit code 0 | **PASSED** |
| **A-401.2** | Inventory Graph Resolution | `ansible-inventory --graph` | Graph resolves `managed_lab`, `webservers`, `forgeops-node-01` | **PASSED** |
| **A-401.3** | Live SSH Ping Connectivity | `ansible managed_lab -m ping` | `"ping": "pong"` | **PASSED** |
| **A-401.4** | Full Playbook Convergence (initial) | `ansible-playbook site.yml --ask-become-pass` | All 5 roles; `ok=35 changed=0 failed=0` | **PASSED** |
| **A-401.4b** | Full Playbook Convergence (post sudo-policy update) | `ansible-playbook site.yml --ask-become-pass` | All 5 roles; `ok=36 changed=0 failed=0 skipped=1` | **PASSED** |
| **A-401.5** | Nginx HTTP Health Endpoint | Verified via `verify.yml` audit (`ansible.builtin.uri`) | HTTP 200, `{"status":"UP"}` | **PASSED** |
| **A-401.6** | Firewall External Port Block Test | `curl --noproxy '*' --connect-timeout 3 --max-time 6 http://192.168.96.1:28088/` | Blocked (exit 28 after ~6s) → Allowed (exit 0) → Blocked (exit 28 after ~6s) | **PASSED** |
| **A-402.1** | Idempotence Verification | `ansible-playbook site.yml --ask-become-pass` (consecutive run) | `changed=0, failed=0` on full second run | **PASSED** |
| **A-402.2** | Non-Mutating Audit Playbook | `ansible-playbook playbooks/verify.yml` | `ok=14 changed=0 failed=0 skipped=1` | **PASSED** |
| **DR-09** | Nginx Configuration Drift Recovery | Drift injected at line 35; `site.yml` reapplied | `ok=37 changed=2 failed=0`; `/health` returns 200 post-recovery | **PASSED** |

### A-401.6 Firewall External Port Block Test Detail

Per `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` (§G04 acceptance: *"firewall blocks designated test port without blocking SSH"*), external port blocking was independently verified using a controlled three-phase (blocked → temporarily allowed → blocked) protocol with positive control:

1. **Test Environment & Setup:**
   - VirtualBox NAT forwarding temporarily mapped Windows WSL gateway address `192.168.96.1:28088` to guest TCP port `8088` (rule name `g04-porttest`).
   - A dedicated temporary Python HTTP listener ran inside the Ubuntu guest bound to port `8088`.
   - Internal guest baseline test: `curl http://127.0.0.1:8088` confirmed the listener was active and returning `FORGEOPS-G04-PORTTEST-OK`.
   - External HTTP requests were executed from the WSL2 Ubuntu controller against the VirtualBox NAT forwarding endpoint `http://192.168.96.1:28088/`.

2. **Phase 1 — Blocked State Verification:**
   - With guest port `8088` blocked by default UFW incoming deny policy:
   - External execution (from WSL Ubuntu): `curl --noproxy '*' --connect-timeout 3 --max-time 6 http://192.168.96.1:28088/`
   - Result: Verbose curl output explicitly demonstrated a successful initial TCP connection to the VirtualBox forwarding endpoint (`192.168.96.1:28088`), followed by an HTTP response timeout with zero bytes received from the guest due to UFW dropping incoming packets. The command exited with **exit code 28** after approximately 6 seconds.

3. **Phase 2 — Positive Control (Temporarily Allowed):**
   - Temporarily added UFW rule allowing `8088/tcp` (`ufw allow 8088/tcp`).
   - External execution (from WSL Ubuntu): `curl --noproxy '*' --connect-timeout 3 --max-time 6 http://192.168.96.1:28088/`
   - Result: Succeeded with **exit code 0**, returning payload `FORGEOPS-G04-PORTTEST-OK` (the external positive-control command did not explicitly print the HTTP status code).
   - Confirms that the end-to-end network path through VirtualBox NAT forwarding was fully operational and that UFW was the sole blocking mechanism.

4. **Phase 3 — Blocked Re-verification:**
   - Removed temporary UFW rule for `8088/tcp` (`ufw delete allow 8088/tcp`).
   - External execution (from WSL Ubuntu): `curl --noproxy '*' --connect-timeout 3 --max-time 6 http://192.168.96.1:28088/`
   - Result: Verbose curl output again showed successful connection to the forwarding endpoint followed by an HTTP response timeout with zero bytes received, exiting with **exit code 28** after approximately 6 seconds.

5. **SSH Verification:**
   - SSH key-based access to the guest remained functional; SSH connections succeeded during the workflow and were explicitly verified working following the blocked-port test.

6. **Verified Lab Cleanup:**
   - Temporary VirtualBox NAT forwarding rule `g04-porttest` removed.
   - Preserved VirtualBox SSH forwarding rule verified active: `guestssh,tcp,192.168.96.1,2222,,22`.
   - Temporary Python HTTP listener stopped, port 8088 listener removed, and test directory/files removed from guest.
   - UFW status confirmed active with incoming policy set to deny and only intended inbound allowances for `22/tcp` and `80/tcp`.
   - Nginx service active; `/health` endpoint returned HTTP 200 with `status: UP`.

7. **Post-Test Convergence & Independent Audit:**
   - Post-cleanup full playbook convergence (`ansible-playbook site.yml --ask-become-pass`):
     `ok=36 changed=0 unreachable=0 failed=0 skipped=1`.
   - Post-cleanup independent audit (`ansible-playbook playbooks/verify.yml`):
     `ok=14 changed=0 unreachable=0 failed=0 skipped=1` (confirmed password-required sudo, SSH hardening, UFW active, Nginx active, HTTP health 200).

### A-402 Audit Detail

Final `verify.yml` run confirmed:
- Timezone `Etc/UTC` ✓
- `ops` user present in `/etc/passwd` ✓
- `ops` is a member of the `sudo` group ✓
- `NOPASSWD` absent from `sudo -l` output (policy: `ops_sudo_nopasswd = false`) ✓
- `00-forgeops-hardening.conf` present, `99-forgeops-hardening.conf` absent ✓
- `sshd -T` effective values: `passwordauthentication no`, `permitrootlogin no`, `pubkeyauthentication yes` ✓
- UFW status: active ✓
- Nginx systemd `ActiveState`: active ✓
- HTTP `/health` response: 200 ✓

### DR-09 Drift Recovery Detail

- Drift introduced: `# DR-09-INTENTIONAL-DRIFT` comment injected at line 35 of the live Nginx site config.
- Drift confirmed present before recovery run.
- Recovery run: `ok=37 changed=2 failed=0` — Nginx template corrected; Nginx configuration validated and reloaded by handler.
- Drift marker confirmed removed post-recovery.
- Post-recovery full convergence: `ok=35 changed=0 failed=0`.

---

## 7. Offline Validation Execution Evidence

Executed inside WSL2 Ubuntu controller:
```bash
$ make ansible-check
============================================================
 ForgeOps G04 Ansible Offline Syntax & Structure Validation
 2026-10-25T05:29:02Z
 Repo: /mnt/c/Project/ForgeOps
============================================================
[INFO] Checking Ansible controller tooling baseline...
[PASS] Ansible detected: ansible [core 2.17.7]
[PASS] Python runtime: Python 3.12.3
[PASS] OpenSSH client: OpenSSH_9.6p1 Ubuntu-3ubuntu13.20, OpenSSL 3.0.13 30 Jan 2024
[WARN] ansible-lint is not installed (optional offline linter; see docs for installation via pipx)
[INFO] Verifying required Ansible collections...
[PASS] Collection ansible.posix is installed
[PASS] Collection community.general is installed
[INFO] Testing Ansible inventory graph parsing...
[PASS] Inventory parsed successfully (managed_lab, webservers, forgeops-node-01)
[INFO] Validating site.yml playbook syntax...
[PASS] Playbook site.yml syntax valid across all 5 roles (baseline, users, ssh-hardening, firewall, nginx)
[INFO] Validating verify.yml audit playbook syntax...
[PASS] Audit playbook verify.yml syntax valid
------------------------------------------------------------
 Historical Runtime Guest Execution Evidence:
 Note: Recorded runtime results below are historical evidence,
 NOT live tests executed by this offline check script.
 See docs/evidence/G04/readiness.md for full execution evidence.
 [RECORDED] Managed guest VM verified and pingable
 [RECORDED] A-401: Full site playbook convergence on live guest
 [RECORDED] A-401.6: External firewall port block test (drop verified)
 [RECORDED] A-402: Playbook idempotence (changed=0) on live guest
 [RECORDED] DR-09: Intentional Nginx configuration drift correction
 [RECORDED] Independent audit: verify.yml (ok=14 changed=0 failed=0)
------------------------------------------------------------
============================================================
 Validation Summary: 8 Passed, 0 Failed, 1 Warning(s)
============================================================
Status: PASSED (Offline Scaffolding & Syntax Validated)

Note: The make ansible-check log above validates offline syntax and structure.
All recorded runtime results reflect historical evidence executed on the live guest VM.
```

---

## 8. Conclusion & Acceptance Status

All G04 acceptance criteria defined in `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` (§G04) have been fully verified against the live Ubuntu Server 24.04.5 LTS guest:

- **A-401 Full Convergence:** PASSED — All five roles executed cleanly (`ok=36 changed=0 failed=0 skipped=1`).
- **A-401.6 Firewall External Port Drop:** PASSED — External blocked-port verification confirmed UFW drops unallowed traffic (exit 28 after ~6s) with positive control (exit 0 returning FORGEOPS-G04-PORTTEST-OK) and re-blocking (exit 28 after ~6s); SSH access verified working; cleanup and post-test zero-change convergence verified.
- **A-402 Idempotence:** PASSED — Consecutive full `site.yml` run reported `changed=0, failed=0`.
- **DR-09 Drift Recovery:** PASSED — Nginx configuration drift detected and corrected by `site.yml`; service verified healthy post-recovery (`ok=37 changed=2 failed=0`).
- **Independent Audit:** PASSED — `verify.yml` confirmed all desired-state assertions including sudo group membership, NOPASSWD policy enforcement, SSH hardening, UFW, Nginx, and HTTP health endpoint (`ok=14 changed=0 failed=0 skipped=1`).

Security controls active at gate closure:
- Strict cryptographic host-key verification enforced (`host_key_checking = True`).
- Anti-lockout safeguards and cloud-init precedence ordering active.
- Public key deployed without private key exposure in Git.
- UFW allows SSH before enforcing default deny; SSH port explicitly open.
- Password-required sudo policy enforced (`ops_sudo_nopasswd: false`); `NOPASSWD` absent from sudoers.
- SSH candidate staged, validated with `sshd -t`, and effective values asserted with `sshd -T` before reload.

**Gate G04 technical acceptance: PASSED — PENDING PR REVIEW AND MERGE.**
All mandatory G04 criteria are satisfied. Final closure is subject to GitHub PR review and merge approval. No unreviewed code is on `master`.
