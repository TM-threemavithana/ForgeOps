# ADR-0014: Terraform Lifecycle Boundaries, Resource Ownership, and Local State Governance

- **Status:** Accepted (Gate G05)
- **Date:** 2026-10-25
- **Deciders:** Principal DevOps Engineer, Infrastructure Architect, Security Reviewer

---

## 1. Context

ForgeOps operates a multi-tool delivery platform incorporating Docker Compose (local development), Ansible (Linux guest OS configuration), Kind (local Kubernetes runtime), and Argo CD (declarative GitOps). Gate G05 introduces **Terraform** as the Infrastructure as Code (IaC) provisioning tool for local resources.

Without strict ownership and lifecycle boundaries, introducing Terraform alongside existing tools risks:
1. **Ownership Collisions:** Terraform attempting to manage containers, networks, or volumes created by Docker Compose or Kind.
2. **State Poisoning & Cascading Destruction:** A generic `terraform destroy` command inadvertently wiping out running Compose stacks (`forgeops-api`, `forgeops-postgres`), Kind cluster nodes, or unrelated developer workloads (`realmcanvas_*`).
3. **State Secret Leaks:** Committing `terraform.tfstate` containing sensitive resource attributes, filesystem metadata, or internal IPs to public Git repositories.
4. **Coupled Root Modules:** Coupling local diagnostic fixtures with Kubernetes cluster bootstrapping, inflating the blast radius and preventing independent testing.

---

## 2. Options Considered

### Option 1: Terraform Owns All Local Docker Resources
Use Terraform's Docker provider to manage the Docker Compose application stack (`forgeops-api`, `postgres`) and the Kind cluster container itself.
- *Downsides:* Violates the Sole Owner Contract (ADR-0003); creates tight coupling between developer Compose workflows (`docker compose up`) and Terraform state; risks accidental deletion of database volumes.

### Option 2: Terraform Manages Kind and Argo CD in a Monolithic Root Module
Use a single Terraform configuration to spin up Docker resources, create Kind nodes, and install Helm releases.
- *Downsides:* High blast radius; violates local-first separation; leads to massive state files that are slow to refresh; risks destroying Kubernetes clusters during local fixture testing.

### Option 3: Strictly Scoped Local Diagnostic Module with Independent State (Selected)
Isolate Gate G05 to a dedicated root module (`infrastructure/terraform/local-docker-lab`) that owns exclusively its own isolated network, diagnostic container, and image reference. Separate all Kubernetes bootstrapping into an independent, future module (`infrastructure/terraform/cluster-bootstrap`).

---

## 3. Decision

We adopt **Option 3** with the following structural rules:

### 3.1 Strict Sole Owner Contract for G05
- **Terraform `local-docker-lab` module owns exclusively:**
  - 1 Docker network: `forgeops-iac-lab` (bridge driver, automatic subnet allocation).
  - 1 Diagnostic container: `forgeops-diag-fixture` (pinned image `nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951`).
  - 1 Docker image resource reference: `docker_image.fixture` with `keep_locally = true`.
- **Terraform explicitly does NOT own:**
  - Docker Compose application stack (`forgeops-api`, `forgeops-postgres`, `forgeops-g02-net`, `forgeops-g02-postgres-data`).
  - Kind Kubernetes cluster containers, nodes, or volumes.
  - Unrelated host or user containers (`realmcanvas_*`, `docker-kafka-*`).
  - VirtualBox guest virtual machine (`forgeops-ansible-lab`), OS configuration, or UFW firewall (owned exclusively by Ansible).

### 3.2 Independent State Governance & Protection
- State is stored locally in `/home/tharuka/.local/state/forgeops/g05/terraform.tfstate` completely outside the Git repository.
- State directory permissions are restricted to `0700` (`drwx------`) and files to `0600` (`-rw-------`).
- Local state files (`*.tfstate`, `*.tfstate.*`, `*.tfstate.backup`, `.terraform/`, `tfplan`, `tfplan*`, `*.tfplan`, `*.plan`) are strictly excluded from Git via `.gitignore`.
- Provider dependency lockfile (`.terraform.lock.hcl`) is committed to Git to enforce reproducible provider binary hashes.
- Pre-destruction and pre-apply state backups are stored outside the repository in `/home/tharuka/.local/state/forgeops/g05/backups/`.

### 3.3 Security & Network Isolation
- All exposed ports bind strictly to host loopback (`127.0.0.1:8089 -> 80`). Binding to wildcard `0.0.0.0` is strictly prohibited by variable validation.
- All managed resources carry explicit OCI/ForgeOps labels:
  - `org.opencontainers.image.vendor = "ForgeOps"`
  - `forgeops.io/managed-by = "terraform"`
  - `forgeops.io/gate = "G05"`
  - `forgeops.io/role = "diagnostic-fixture"`

---

## 4. Consequences & Trade-offs

### Positive
- **Zero Blast Radius:** Verified via A-502. Running `terraform destroy` in `local-docker-lab` removed only `forgeops-diag-fixture` and `forgeops-iac-lab`. Compose and RealmCanvas workloads remained healthy and untouched.
- **Clear Drift Detection:** Verified via DR-10. Stopping the container out-of-band was detected as drift and rectified via Terraform without collateral damage.
- **Reproducible Local Testing:** No cloud accounts, credentials, or paid APIs required.

### Negative / Limitations
- Local state is tied to the single operator workstation; not shared across multiple developer machines (acceptable under ForgeOps portfolio constraints).
- Requires explicit Make targets or path scoping (`cd infrastructure/terraform/local-docker-lab`) to prevent running commands in the wrong directory.

---

## 5. Verification Evidence (Completed 2026-10-25)

1. **Static Validation:** `terraform fmt -check` and `terraform validate` passed with clean exit code 0.
2. **Scoped Lifecycle (A-501):** `terraform apply` created exactly 3 resources (`docker_image.fixture`, `docker_network.iac_lab`, `docker_container.diag_fixture`). HTTP 200 verified on `127.0.0.1:8089`.
3. **Idempotence (A-501.5):** Resolved initial `memory_swap` drift by explicitly setting `memory_swap = var.memory_limit_mb * 2`. Post-correction `terraform plan -detailed-exitcode` returned exit code 0 ("No changes").
4. **Drift Recovery (DR-10):** Stopping `forgeops-diag-fixture` out-of-band triggered `Plan: 1 to add, 0 to change, 1 to destroy`. Applying recovery restored container with HTTP 200 while preserving network ID.
5. **Safe Teardown (A-502):** Destroy plan executed cleanly (`3 destroyed`). `terraform state list` is empty. Preexisting workloads (`realmcanvas_*`) remained completely untouched.
