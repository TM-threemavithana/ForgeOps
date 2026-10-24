# ADR-0005: State Isolation and Host-Side Persistence Strategy

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
In local platform engineering environments, persistent state exists across two distinct layers:
1. **Terraform State Files:** Contain sensitive configuration metadata, resource IDs, and provider state. Storing state in Git risks credential leakage and merge conflicts. Storing state in a shared root causes massive blasted blast radiuses.
2. **Kubernetes Storage (PostgreSQL PVCs):** Kind nodes run as ephemeral Docker containers. Recreating a Kind cluster deletes all internal node mounts and local storage volumes, risking catastrophic data loss.

## Options Considered
1. **Cloud Remote State & Managed Database (S3/DynamoDB + AWS RDS):** Violates the zero-cloud-cost hard boundary.
2. **Commit Terraform State & Rely on Kind Node Volumes:** Exposes state secrets in Git; results in total data loss upon any `kind delete cluster` command.
3. **Independent Local Terraform Backends & Host-Side Database Backups:** Separate local state files per Terraform root, coupled with automated host-side `pg_dump` backups outside Kind container volumes.

## Decision
Adopt **State Isolation and Host-Side Persistence**:
1. **Independent Terraform Roots:**
   - `infrastructure/terraform/local-docker-lab` and `infrastructure/terraform/cluster-bootstrap` maintain independent local state files on the operator filesystem.
   - All `*.tfstate*` files are strictly excluded from Git via `.gitignore`.
2. **Host-Side Database Backups:**
   - PostgreSQL persistence uses local PersistentVolumeClaims bound via standard Kind storage classes.
   - Backups are orchestrated using `pg_dump` executed from host automation (`make backup-db`), storing compressed, timestamped dumps with SHA256 checksums in a private host directory (`~/.config/forgeops/backups/`).
   - Backups are stored completely outside Docker container volumes, ensuring data survives complete Kind cluster resets.
3. **Verification Before Reset:**
   - Cluster recreation runbooks mandate taking a host-side snapshot and running `make verify-backup` into a scratch database before executing `kind delete cluster`.

## Consequences & Trade-offs
### Positive:
- **Resilience Against Cluster Destruction:** Kind clusters can be torn down and rebuilt from scratch without losing PostgreSQL business records.
- **Blast Radius Containment:** Corrupting the local Docker lab state has zero effect on the cluster bootstrap state.
- **No Secret Leaks:** Terraform state containing resource metadata is never pushed to public Git remotes.

### Negative / Limitations:
- Local state files are not automatically synchronized between multiple machines (single-operator model).
- Loss of the host filesystem (`C:`) destroys local state if host backups are not maintained.

## Verification Tests
- `git status` verifies `terraform.tfstate` is untracked and ignored.
- `make backup-db` produces a valid `.sql.gz` dump and SHA256 file in the host backup directory.
- `make verify-backup` restores the dump into a disposable database container and confirms row counts match.

## Reconsideration Triggers
- Introduction of local MinIO S3-compatible backend storage if multi-operator state locking is required in advanced phases.
