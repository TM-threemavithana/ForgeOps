# ForgeOps G05 — Local Docker Lab Terraform Module

This module provisions and manages the Gate G05 local Docker infrastructure lab using HashiCorp Terraform and the `kreuzwerker/docker` provider.

## Architecture & Resource Ownership

The module manages exactly three Terraform-owned resources:

1. **`docker_image.fixture`**: Diagnostic HTTP image pinned to verified registry digest (`nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951`) with `keep_locally = true`.
2. **`docker_network.iac_lab`**: Isolated Docker bridge network (`forgeops-iac-lab`) with automatic subnet allocation.
3. **`docker_container.diag_fixture`**: Disposable diagnostic HTTP fixture (`forgeops-diag-fixture`) bound exclusively to `127.0.0.1:8089`.

### Resource Boundaries

- **Single Ownership Principle**: Terraform owns only the three resources declared in this module. Existing application containers (`realmcanvas_app`, `realmcanvas_db`), compose stacks, Kafka brokers, and networks (`forgeops-g02-net`, `realmcanvas_default`, `docker_default`) are unmanaged and protected.
- **Network Isolation**: The diagnostic container attaches exclusively to `forgeops-iac-lab`. It does not bridge to existing Docker application networks.
- **Port Security**: Port 80 is published strictly on `127.0.0.1:8089`. Host-wide (`0.0.0.0`) binding is prevented by input variable validation.
- **Resource Constraints**: Container memory is bounded to 128MB (`memory_limit_mb`), memory swap explicitly configured to 256MB (`memory_swap = var.memory_limit_mb * 2`) to align with Docker daemon default swap allocation, and CPU shares to 512 (`cpu_shares`).
- **Drift Detectability**: Container is configured with `restart = "no"` and `must_run = true`. A deliberate `docker stop` during DR-10 causes Terraform plan/refresh to immediately report state drift.

## State and Plan Storage Security

Terraform state and plan artifacts are stored completely outside the Windows-mounted Git repository:

- **State File Path**: `~/.local/state/forgeops/g05/terraform.tfstate`
  (Absolute Linux path: `/home/tharuka/.local/state/forgeops/g05/terraform.tfstate`)
- **Saved Plan Path**: `~/.local/state/forgeops/g05/forgeops-g05.tfplan`
- **Directory Permissions**: `0700` (`drwx------`) owned by `tharuka:tharuka`.
- **Initialization & Plan Umask**: `0077` ensures state, lock, and plan files remain unreadable by unprivileged users.
- **Git Protection**: `tfplan`, `tfplan*`, `*.tfplan`, `*.plan`, `*.tfstate`, `*.tfvars`, and `.terraform/` are strictly ignored by `.gitignore`. The provider dependency lockfile `.terraform.lock.hcl` is committed to ensure cryptographic reproducibility across environments.

### State Backup Procedure

Before executing any state-mutating operations or plan reviews:

```bash
mkdir -p ~/.local/state/forgeops/g05/backups
cp -p ~/.local/state/forgeops/g05/terraform.tfstate \
      ~/.local/state/forgeops/g05/backups/terraform.tfstate.$(date +%Y%m%d_%H%M%S).bak
```

## Image Cache & `keep_locally` Rationale

The `docker_image` resource specifies `keep_locally = true`:
- When running `terraform destroy`, Terraform removes the container and network but retains the pulled base image in the Docker daemon cache.
- This prevents redundant registry downloads and avoids rate-limiting issues during rapid teardown-and-rebuild cycles.
- If a complete image purge is desired, it must be performed explicitly via `docker rmi nginx:1.30.6-alpine` after confirmation.

## Operational Lifecycle & Acceptance Verification

All runtime acceptance tests for Gate G05 were executed inside WSL2 using Linux Terraform v1.10.4 and `kreuzwerker/docker` v4.6.0. Following successful acceptance testing, the lab fixture was **intentionally destroyed** in accordance with A-502 to conserve host workstation resources.

> **Note on Post-Destroy State:** Because the HCL configuration continues to declare the three resources, running `terraform plan` in the post-destroy state is expected to propose recreating the 3 resources (`3 to add, 0 to change, 0 to destroy`). Zero diff applies only while the infrastructure is actively provisioned.

### Verified Acceptance Scenarios (PASSED)

1. **A-501.4 (Clean Provisioning):**
   ```bash
   terraform apply ~/.local/state/forgeops/g05/forgeops-g05.tfplan
   # Applied: 3 added, 0 changed, 0 destroyed.
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8089
   # Returned HTTP 200.
   ```

2. **A-501.5 (Full Idempotence):**
   ```bash
   terraform plan -detailed-exitcode -no-color
   # Verified: Exit code 0 ("No changes. Your infrastructure matches the configuration.")
   # Addressed initial memory_swap drift by explicitly setting memory_swap = var.memory_limit_mb * 2.
   ```

3. **DR-10 (Drift Detection & Recovery Drill):**
   ```bash
   # 1. Out-of-band failure injection:
   docker stop forgeops-diag-fixture
   # 2. Drift detection:
   terraform plan -detailed-exitcode -no-color
   # Detected: Exit code 2, 1 to add, 0 to change, 1 to destroy (replacement).
   # 3. Drift remediation:
   terraform apply -auto-approve
   # Restored: New container ID created, network ID preserved, endpoint returned HTTP 200.
   ```

4. **A-502 (Scoped Teardown & Blast Radius Audit):**
   ```bash
   # 1. Generate and verify destroy plan:
   terraform plan -destroy -no-color -out=~/.local/state/forgeops/g05/a502-destroy.tfplan
   # 2. Apply reviewed destroy plan:
   terraform apply ~/.local/state/forgeops/g05/a502-destroy.tfplan
   # Destroyed: 3 resources destroyed, state list empty.
   # 3. Blast radius audit:
   # Unrelated containers (realmcanvas_app, realmcanvas_db) remained healthy and untouched.
   ```

### Reproduction / Diagnostic Commands

```bash
# Check formatting
make tf-fmt

# Validate syntax & schema
make tf-validate

# Inspect provider lock
make tf-providers

# Speculative plan (proposes creating lab fixture)
make tf-plan
```
