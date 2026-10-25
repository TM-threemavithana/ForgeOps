# Gate G05 Acceptance & Readiness Report — Local Terraform Infrastructure

- **Date:** 2026-10-25
- **Evaluator:** Tharuka Madhuwantha Threemavithana (`157876462+TM-threemavithana@users.noreply.github.com`)
- **Role:** Principal DevOps Engineer, Infrastructure Architect & Security Reviewer
- **Gate:** G05 — Local Terraform-Provisioned Infrastructure
- **Technical Acceptance Status:** **PASSED — PENDING PR REVIEW AND MERGE**
- **Repository Branch:** `g05-terraform-local-docker-lab`
- **Base Master Merge Commit:** `5a42c6e` (Merge PR #15: G04 Ansible guest management)
- **Execution Profile:** Core Profile (Local-First, Linux WSL2 Execution, Strict Sequential Flow)

---

## 1. Executive Summary & Gate Scope

Gate G05 establishes declarative Infrastructure as Code (IaC) provisioning using the Terraform CLI and the `kreuzwerker/docker` provider. In accordance with **Rule 1** (Zero Paid Cloud Dependency), **Rule 3** (Single Owner Per Resource), and **Rule 4** (Protect User Machine) in `AGENTS.md`, G05 provisions an isolated local container fixture on Docker Engine without modifying existing Compose, Kubernetes, or host workloads.

All G05 acceptance criteria have been executed, verified, and **PASSED**:
1. **A-501 (Clean Convergence & Idempotence):** Successfully applied initial plan creating 3 resources. HTTP 200 verified on `127.0.0.1:8089`. Investigated and resolved initial `memory_swap` drift by explicitly declaring `memory_swap = var.memory_limit_mb * 2`, achieving clean idempotence (`terraform plan -detailed-exitcode` returned exit code 0).
2. **DR-10 (Drift Detection & Recovery Drill):** Injected failure by stopping `forgeops-diag-fixture` out-of-band. Drift was immediately detected (exit code 2). Terraform safely replaced the stopped container while preserving the network ID. Fixture health was restored (HTTP 200) and zero drift re-verified.
3. **A-502 (Scoped Teardown & Blast Radius Audit):** Executed a reviewed destroy plan (`3 destroyed`). Verified `terraform state list` is empty and G05 resources were removed. Preexisting workloads (`realmcanvas_app`, `realmcanvas_db`, etc.) remained healthy and completely untouched.

> **Intentional Post-Acceptance Teardown:** The G05 local lab has been intentionally destroyed following A-502 testing to conserve workstation resources under the Core Profile.
>
> **Note on Post-Destroy State:** Because the HCL configuration continues to declare the three resources, running a speculative `terraform plan` in the post-destroy state is expected to propose recreating the 3 resources (`3 to add, 0 to change, 0 to destroy`). Zero diff applies only while the infrastructure is actively provisioned.

---

## 2. Verified Host & Toolchain Baseline

### 2.1 Toolchain Telemetry
- **WSL2 Controller Terraform:** `Terraform v1.10.4 on linux_amd64` (installed at `/usr/bin/terraform`).
- **Windows Host Terraform:** `Terraform v1.11.3 on windows_amd64` (deferred; Linux execution path strictly enforced for G05).
- **Docker Engine:** `29.5.3 (API version 1.54)` via Docker Desktop 4.77.0 (WSL2 engine).
- **Docker Transport:** WSL2 Unix socket `/var/run/docker.sock` (`srw-rw---- 1 root docker`).
- **Loopback Fixture Port:** `127.0.0.1:8089` (dedicated loopback binding).
- **Hypervisor / VM Status:** VirtualBox VM `forgeops-ansible-lab` running from G04; completely isolated and untouched.

### 2.2 Provider Resolution & Cryptographic Verification
- **Target Provider:** `registry.terraform.io/kreuzwerker/docker`
- **Constraint:** `~> 4.6.0`
- **Resolved Version:** `v4.6.0`
- **Signing Key ID:** `0DCE698927DAF8EC`
- **Terraform CLI Constraint:** `>= 1.10.0, < 2.0.0`
- **Lockfile Checksum Status:** 12 platform hashes recorded in `infrastructure/terraform/local-docker-lab/.terraform.lock.hcl`.

### 2.3 Pinned Image Reference & OCI Verification
- **Image Repository:** `library/nginx`
- **Selected Tag:** `1.30.6-alpine` (Docker Official actively supported stable-Alpine release)
- **Multi-arch Manifest List Digest:** `sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951`
- **Linux AMD64 Image Digest:** `sha256:84ed8c0dd296c188bfc24ed506f46589e9285fb0b11cf3a04d91d524d3067e11`
- **Configured Reference in HCL:**
  ```hcl
  nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951
  ```
- **Digest Validation:** Pinned with strict regex condition `can(regex("@sha256:[a-f0-9]{64}$", var.fixture_image))`.

---

## 3. Verified A-501 Implementation Results (Convergence & Idempotence)

### 3.1 Initial Provisioning (A-501.4)
- **Execution:** Applied reviewed saved plan `forgeops-g05.tfplan`.
- **Result:**
  ```text
  Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
  ```
- **Managed Resources Created:**
  1. `docker_image.fixture`
  2. `docker_network.iac_lab` (`forgeops-iac-lab`)
  3. `docker_container.diag_fixture` (`forgeops-diag-fixture`)
- **Endpoint Verification:**
  ```bash
  $ curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8089/
  200
  ```
- **Workload Protection:** `realmcanvas_app` and `realmcanvas_db` remained Up and healthy.

### 3.2 Idempotence Finding & Resolution (A-501.5)
- **Initial Post-Apply Plan:** Returned exit code 2:
  ```text
    ~ memory_swap = 256 -> null
  Plan: 0 to add, 1 to change, 0 to destroy.
  ```
- **Investigation:** A state backup was secured (`0600`). Docker inspect was executed:
  ```bash
  $ docker inspect forgeops-diag-fixture --format 'Memory: {{.HostConfig.Memory}}, MemorySwap: {{.HostConfig.MemorySwap}}'
  Memory: 134217728, MemorySwap: 268435456
  ```
  *Root Cause:* When Docker daemon creates a container with memory limits but `--memory-swap` is omitted, the daemon automatically defaults `MemorySwap` to 2× `Memory` (128 MB × 2 = 256 MB). The provider recorded 256 in state; subsequent plans compared HCL (`memory_swap = null`) against state (`memory_swap = 256`).
- **Correction:** In `main.tf`, explicitly configured:
  ```hcl
  memory      = var.memory_limit_mb
  memory_swap = var.memory_limit_mb * 2
  ```
  Refused `lifecycle { ignore_changes = [memory_swap] }` or manual state manipulation.
- **Retest Verification:**
  ```bash
  $ terraform plan -detailed-exitcode -no-color
  No changes. Your infrastructure matches the configuration.
  ```
  *Exit Code:* **0** (Idempotence confirmed).
- **Result:** **A-501 PASSED**.

---

## 4. Verified DR-10 Results (Intentional Drift Recovery Drill)

### 4.1 Controlled Failure Injection
- **Ownership Verification:** Confirmed `forgeops-diag-fixture` was labeled `forgeops.io/managed-by = "terraform"` and attached to `forgeops-iac-lab`.
- **Action:** Executed out-of-band `docker stop forgeops-diag-fixture`. Preexisting RealmCanvas and Compose workloads were untouched.

### 4.2 Drift Detection
- **Command:** `terraform plan -detailed-exitcode -no-color`
- **Result:** Exit code **2**.
- **Proposed Action:**
  ```text
  Plan: 1 to add, 0 to change, 1 to destroy.
  ```
- **Rationale for Replacement:** The resource definition specifies `restart = "no"` and `must_run = true`. When the container is stopped out-of-band, the `kreuzwerker/docker` provider detects that the running state constraint is violated and plans replacement to ensure a clean running container.

### 4.3 Recovery Execution & Verification
- **Execution:** Applied reviewed recovery plan.
  ```text
  Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
  ```
- **Container ID Tracking:**
  - Original Container ID: `c8d9d9e0f04b3b594a2800d77903605f65318ba057af7aaf33348bba636b44e3`
  - Recovered Container ID: `25589617f1b2cc34f3f071f02022b66e46f3e2e3472455cafc48f2c50f914380`
- **Network Preservation:**
  - Preserved Network ID: `5711c55e36169b0f84cb606883637fb62c906e9929bb0a45b229c9369e9da038`
- **Post-Recovery Health & Idempotence:**
  - Diagnostic endpoint returned **HTTP 200**.
  - RealmCanvas application and database remained healthy.
  - Subsequent `terraform plan -detailed-exitcode -no-color` returned **exit code 0** (zero drift).
- **Result:** **DR-10 PASSED**.

---

## 5. Verified A-502 Results (Scoped Teardown & Blast Radius Audit)

### 5.1 Pre-Destroy Safeguards
- Verified Terraform state contained exactly the three G05 resources.
- Confirmed only `forgeops-diag-fixture` was attached to `forgeops-iac-lab`.
- Captured pre-destroy baseline inventories for containers, networks, and volumes.
- Created post-recovery state backup (`0600`) in `/home/tharuka/.local/state/forgeops/g05/backups/`.

### 5.2 Destroy Plan & Execution
- **Saved Destroy Plan:** `/home/tharuka/.local/state/forgeops/g05/a502-destroy.tfplan`
- **Plan Verification:**
  - `docker_container.diag_fixture`: destroy
  - `docker_image.fixture`: destroy
  - `docker_network.iac_lab`: destroy
  - `Plan: 0 to add, 0 to change, 3 to destroy.`
- **Execution:** Applied reviewed destroy plan.
  ```text
  Apply complete! Resources: 0 added, 0 changed, 3 destroyed.
  ```

### 5.3 Post-Destroy Verification
- **State Audit:** `terraform state list` returned empty (0 resources).
- **Container Audit:** `docker ps -a --filter name=forgeops-diag-fixture` returned 0 containers.
- **Network Audit:** `docker network ls --filter name=forgeops-iac-lab` returned 0 networks.
- **Endpoint Audit:** `curl -s http://127.0.0.1:8089` failed with exit code 7 (connection refused; port released).
- **Image Retention Note:** The Nginx image resource was configured with `keep_locally = true`, so retaining base image layers in the local Docker daemon cache is the intended and expected behavior.

### 5.4 Blast Radius Audit (Non-Interference Checks)
Before-and-after comparison confirmed complete workload isolation:
- **Protected Containers:** `realmcanvas_app` and `realmcanvas_db` remained Up and healthy throughout. Compose containers remained in their preexisting stopped state.
- **Protected Networks:** `bridge`, `docker_default`, `forgeops-g02-net`, `host`, `none`, `realmcanvas_default` were completely unaffected.
- **Protected Volumes:** `forgeops-g02-postgres-data`, `realmcanvas_pgdata`, `docker_streamforge-*` were completely unaffected.
- **VirtualBox VM:** `forgeops-ansible-lab` remained completely isolated and untouched.
- **Result:** **A-502 PASSED**.

---

## 6. Acceptance Test Matrix Summary

| Test ID | Scenario | Verified Execution Evidence | Status |
|---|---|---|---|
| **A-501.1** | Static Formatting | `terraform fmt -check -recursive`: Clean exit code 0 | **PASSED** |
| **A-501.2** | Schema Validation | `terraform validate`: "Success! The configuration is valid." | **PASSED** |
| **P-500.1** | Provider Resolution | `terraform providers`: `kreuzwerker/docker ~> 4.6.0` locked | **PASSED** |
| **P-500.2** | Lockfile Checksum | `.terraform.lock.hcl`: 12 platform hashes with key `0DCE698927DAF8EC` | **PASSED** |
| **P-500.3** | Saved Plan Security | Saved to `~/.local/state/forgeops/g05/forgeops-g05.tfplan` (0600) | **PASSED** |
| **A-501.3** | Plan Review | `terraform show -no-color`: 3 to add, 0 to change, 0 to destroy | **PASSED** |
| **A-501.4** | Clean Convergence | `terraform apply`: 3 added, 0 changed, 0 destroyed; HTTP 200 | **PASSED** |
| **A-501.5** | Plan Idempotence | `terraform plan -detailed-exitcode`: Exit code 0 ("No changes") | **PASSED** |
| **DR-10** | Drift Recovery | Out-of-band stop detected (code 2); apply restored container; HTTP 200 | **PASSED** |
| **A-502.1** | Scoped Destruction | Destroy plan applied: 3 destroyed; state list empty; port released | **PASSED** |
| **A-502.2** | Blast Radius Audit | RealmCanvas healthy; zero collateral damage across containers/networks | **PASSED** |

---

## 7. Runtime Evidence vs. Offline Validation

To maintain rigorous traceability, historical runtime results are distinguished from offline static validations:

### 7.1 Historical Runtime Results (Executed on WSL Docker Daemon)
- **A-501.4 Apply:** Timestamp 2026-10-25 21:28 IST (`c8d9d9e0f04b`, HTTP 200).
- **A-501.5 Idempotence Retest:** Timestamp 2026-10-25 21:34 IST (exit code 0).
- **DR-10 Recovery:** Timestamp 2026-10-25 21:45 IST (`25589617f1b2`, network `5711c55e3616`).
- **A-502 Destruction:** Timestamp 2026-10-25 21:55 IST (3 destroyed, state list empty).

### 7.2 Offline Static Validation Results (Independent of Docker State)
```bash
$ cd infrastructure/terraform/local-docker-lab && terraform fmt -check -recursive
(Clean exit code 0)

$ cd infrastructure/terraform/local-docker-lab && terraform validate
Success! The configuration is valid.

$ cd infrastructure/terraform/local-docker-lab && terraform providers
Providers required by configuration:
.
└── provider[registry.terraform.io/kreuzwerker/docker] ~> 4.6.0
```

---

## 8. State and Artifact Governance Audit

1. **State Isolation:**
   - Path: `/home/tharuka/.local/state/forgeops/g05/terraform.tfstate`
   - File Mode: `0600` (`-rw-------`), directory mode: `0700` (`drwx------`).
   - Completely external to Git working tree and Windows mount.
2. **Backup History:**
   - Pre-destruction and post-recovery backups stored under `/home/tharuka/.local/state/forgeops/g05/backups/`.
3. **Repository Cleanliness (.gitignore):**
   - Verified that `*.tfstate*`, `tfplan*`, `*.tfplan`, `*.plan`, and `.terraform/` are strictly excluded.
   - Provider lockfile `.terraform.lock.hcl` is committed to ensure cross-platform reproducibility.
4. **Git Tree Audit:**
   - `git diff --check` and `git diff --cached --check`: Clean exit code 0 (zero whitespace issues).
   - Branch: `g05-terraform-local-docker-lab`.

---

## 9. Gate G05 Technical Acceptance Conclusion

All requirements of Gate G05 from `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` have been fulfilled:
- Local Terraform infrastructure module created and validated.
- Pinned Docker provider v4.6.0 and OCI digest verified.
- Non-destructive plan review verified.
- Clean provisioning (A-501.4) and post-apply idempotence (A-501.5) verified.
- Controlled drift detection and remediation (DR-10) verified.
- Scoped teardown with zero collateral blast radius (A-502) verified.
- The local lab fixture was intentionally destroyed post-acceptance.

**Technical Acceptance Status:** **PASSED — PENDING PR REVIEW AND MERGE**
