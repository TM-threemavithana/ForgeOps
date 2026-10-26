# ForgeOps Gate G08 — Terraform Cluster Bootstrap Module

This module provisions the **Argo CD GitOps Platform** onto the local Kind cluster (`kind-forgeops`) in accordance with `ADR-0003`, `ADR-0004`, and `ADR-0014`.

## 1. Architectural Scope & Sole Owner Contract

In strict compliance with the **Sole Owner Contract (ADR-0003)**:
- **This module owns exclusively:**
  - 1 Kubernetes Namespace: `argocd` (`kubernetes_namespace.argocd`)
  - 1 Helm Release: `argocd` (`helm_release.argocd`, upstream chart `argo/argo-cd:10.11.6`, app version `v3.5.6`)
- **This module explicitly does NOT own:**
  - The Kind cluster containers, control-plane nodes, or Docker networks (owned by `scripts/cluster/`).
  - Application workloads (`forgetasks-api`, `forgetasks-db`), ConfigMaps, or Services in `forgeops-dev` or `forgeops-staging` (outside this Terraform module; protected G06 remains manifest-managed and has not been adopted by Argo CD).
  - The existing persistent volume claim `postgres-storage-forgetasks-db-0` (owned by Flyway / PostgreSQL StatefulSet / Kind local-path storage).
  - Kubernetes Secrets (owned by out-of-band injection `scripts/cluster/inject-secrets.sh`).
  - Local diagnostic fixtures or Docker Compose stacks (owned by `local-docker-lab` and Compose).

## 2. Technology & Version Matrix

| Component | Pinned Version | Source | Rationale |
|---|---|---|---|
| **Terraform CLI** | `>= 1.10.0, < 2.0.0` | HashiCorp | Matches workstation v1.10.4 binary baseline. |
| **Provider `helm`** | `~> 2.17.0` | `hashicorp/helm` | Stable, robust release management engine for Kubernetes. |
| **Provider `kubernetes`** | `~> 2.36.0` | `hashicorp/kubernetes` | Native declarative management of the `argocd` namespace. |
| **Argo CD Helm Chart** | `10.11.6` | `argo/argo-cd` (`https://argoproj.github.io/argo-helm`) | Deploys Argo CD `v3.5.6` matching `docs/compatibility-matrix.md`. |

## 3. Resource Governance (Core Profile)

To adhere to `ADR-0008` (Hardware Execution Profiles) and prevent host OOM kills, `values-argocd-core.yaml` enforces:
1. **HA Disabled:** Single-replica Redis and single-replica controller/server.
2. **Heavy Subsystems Disabled:** Dex (SSO) and Notifications controller are disabled (`dex.enabled: false`, `notifications.enabled: false`), saving ~200 MiB memory and 2 pods.
3. **Strict Resource Bounds:** Requests and limits are configured on all pods (`redis`, `repoServer`, `controller`, `server`, `applicationSet`).
4. **Authentication Enabled:** `configs.cm.admin.enabled: true` ensures authentication is active. The initial admin password is generated dynamically inside Secret `argocd-initial-admin-secret` (no hardcoded passwords or secrets in Git).

## 4. State File Security & Governance (ADR-0014)

State is maintained strictly outside the repository in native-WSL storage:
- **State Path:** `/home/tharuka/.local/state/forgeops/g08/terraform.tfstate`
- **Permissions:** Parent directory `0700` (`drwx------`), state file `0600` (`-rw-------`).
- **Exclusion:** `.gitignore` excludes `*.tfstate`, `*.tfplan`, and `.terraform/`.
- **Lockfile:** `.terraform.lock.hcl` is committed to ensure reproducible provider binary checksums.

## 5. Operator Runbook — Historical Bootstrap Reference

**Important:** Argo CD is already installed, and the active
Terraform state is maintained outside the Git repository.

The initialization, planning, and original apply examples
below describe the bootstrap process. They must not be
replayed against the active environment without an
explicitly authorized, state-aware change procedure.

Any future Terraform plan must use the existing private
state, be reviewed before application, and preserve the
rehearsal workloads, database storage, and protected G06
resources.


### Preflight Verification
Confirm Kind cluster is healthy and context is active:
```bash
kubectl --kubeconfig ~/.kube/config-forgeops config current-context
# Expected: kind-forgeops
```

### Initialization
```bash
cd infrastructure/terraform/cluster-bootstrap
terraform init
```

### Plan Review (Non-Destructive Inspection)
```bash
terraform plan -out=tfplan-g08
```
Verify the plan proposes:
- `+ kubernetes_namespace.argocd`
- `+ helm_release.argocd`
- `Plan: 2 to add, 0 to change, 0 to destroy.`
- **Zero changes to `forgeops-dev`, `forgeops-staging`, or other namespaces.**

### Original Apply Stage (Historical; Not Authorized for Replay)
```bash
# Historical apply command intentionally omitted.
# A fresh, reviewed plan requires separate authorization.
```

### Accessing Argo CD
```bash
# 1. Port-forward to localhost loopback
kubectl --kubeconfig ~/.kube/config-forgeops --context kind-forgeops \
  port-forward svc/argocd-server -n argocd 8080:443

# 2. Retrieve initial admin password dynamically
kubectl --kubeconfig ~/.kube/config-forgeops --context kind-forgeops \
  -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 3. Access https://localhost:8080 (User: admin)
```

### Destructive Teardown Prohibited While Rehearsal Is Active
Do not destroy the Terraform-managed Argo CD installation while it manages the live rehearsal Application. Removing Argo CD can interrupt GitOps reconciliation and must not be represented as harmless cleanup.
```bash
# Destructive Terraform commands are intentionally omitted.
# Require a separately approved teardown and recovery plan.
```
