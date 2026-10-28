# ForgeOps Runbook — PostgreSQL Disaster Recovery & Database Restoration

**Document ID:** `RB-DR-001`  
**Target Workload:** ForgeTasks PostgreSQL 16 Database  
**Author:** ForgeOps Platform & Reliability Engineering  
**Classification:** Operational Runbook — Gate G13  

---

## 1. Overview & Objectives

This runbook defines the emergency operational procedures for backing up, verifying, and recovering the ForgeTasks PostgreSQL database under partial data corruption, container failure, or disaster scenarios.

### Disaster Recovery Targets (Lab Baseline)
- **Recovery Time Objective (RTO):** Target $\le 15$ minutes from incident declaration to verified API traffic resumption.
  - *Restoration Execution Time:* Measured around `pg_restore` (typically $< 3$ seconds).
  - *End-to-End Recovery Time:* Measured from rehearsal initiation to API healthy (typically $< 35$ seconds).
- **Recovery Point Objective (RPO):** Target $\le 24$ hours for scheduled daily snapshots; $\le 5$ minutes for on-demand pre-maintenance snapshots.
  - *Backup Age / Measured RPO:* Calculated from backup creation epoch to restore execution.

---

## 2. Fundamental Safety Constraints

> [!CAUTION]
> **Zero Overwrite Invariant:**  
> Never run `pg_restore` directly over an active, existing database without first establishing a pre-cutover backup.  
> Under no circumstances may restoration overwrite or target `forgeops-dev` or `forgeops-gitops-rehearsal` without explicit, reviewed operator override and secondary approval.

1. **Verify Before Restoring:** Always validate the backup archive's cryptographic SHA-256 checksum and Table of Contents (TOC) using `verify-backup.sh` prior to initiating restoration.
2. **Scratch Database First:** Always restore into a fresh, isolated database instance (in `forgeops-dr-lab`) to verify relational integrity, schema migrations, and row counts before performing any application traffic cutover.
3. **No Secret Leaking:** Never echo, log, or persist database passwords in shell history, logs, or unencrypted text files. Use memory-only variables loaded directly from Kubernetes Secrets.
4. **Preserve Backup Files:** Never delete or overwrite the original backup dump file during restoration or cleanup.
5. **Fresh Database Enforcement:** The target database must be completely empty (0 pre-existing application tables) prior to restoration. `restore-db.sh` refuses to restore if existing schema objects are detected.
6. **Strict Isolation & Distinct Pod UIDs:** Source and target database pods must have distinct Pod UIDs. `backup-db.sh` selects only `dr-source-db` and rejects `dr-target-db`; `restore-db.sh` selects only `dr-target-db` and rejects `dr-source-db`.

---

## 3. Backup Procedure

### Automated Backup Execution

Run the versioned PostgreSQL 16 backup workflow:

```bash
# Default backup targeting disposable lab fixture:
./scripts/cluster/dr/backup-db.sh --source-namespace forgeops-dr-lab --db-name forgetasks

# Makefile shortcut:
make backup-db
```

### What the Backup Script Executes:
1. Validates cluster connectivity (`kind-forgeops`) and all 5 protected PVC baseline UIDs.
2. Asserts source namespace is allowlisted (`forgeops-dr-lab`, `forgeops-dev`, `forgeops-gitops-rehearsal`).
3. Discovers the source database pod strictly (`app=dr-source-db`), verifying owner Deployment and rejecting any pod carrying the target role.
4. Checks filesystem headroom on the destination directory (requires $\ge 250$ MB free).
5. Pre-validates that the source database contains a non-empty dataset before dumping.
6. Connects securely via local port-forward using memory-only credentials from `dr-db-secret`.
7. Executes `pg_dump -Fc -b -v` to a temporary `.tmp` file.
8. Verifies archive readability using `pg_restore -l`.
9. Atomically renames the file to:
   `forgeops-backup-${SOURCE_NS}-${DB_NAME}-${TIMESTAMP}.dump`
10. Computes SHA-256 cryptographic checksum and file size.
11. Generates an immutable manifest file (`.manifest.json`) capturing source database metadata, UTC timestamp, epoch seconds, tool versions, and table catalog.
12. Sets restrictive filesystem permissions (`chmod 0600`).

---

## 4. Verification Procedure

Before initiating any recovery operation, verify the integrity of the backup:

```bash
# Verify using either the .dump file or the .manifest.json:
./scripts/cluster/dr/verify-backup.sh ~/.forgeops/backups/forgeops-backup-<timestamp>.manifest.json

# Makefile shortcut:
make verify-backup BACKUP_FILE=~/.forgeops/backups/forgeops-backup-<timestamp>.dump
```

### Verification Checks Performed:
- **Existence Check:** Confirms both `.dump` and `.manifest.json` files exist.
- **Size Audit:** Verifies actual file byte size matches the declared manifest size.
- **Cryptographic Hash:** Computes live SHA-256 and asserts exact match with manifest.
- **Magic Header:** Confirms initial bytes match `PGDMP` (PostgreSQL custom archive).
- **TOC Catalog:** Runs `pg_restore -l` to verify all required core application tables exist:
  - `flyway_schema_history`
  - `accounts`
  - `projects`
  - `tasks`

> [!NOTE]
> `pg_verifybackup` is deliberately **not** invoked because upstream PostgreSQL restricts `pg_verifybackup` to physical `pg_basebackup` directories. Logical `pg_dump` custom archives are properly verified via SHA-256 and TOC inspection.

---

## 5. Restoration Procedure

Restore the validated backup into a fresh, isolated scratch database:

```bash
# Execute automated safe restoration into disposable lab:
./scripts/cluster/dr/restore-db.sh ~/.forgeops/backups/forgeops-backup-<timestamp>.dump --target-namespace forgeops-dr-lab --target-db forgetasks

# Makefile shortcut:
make restore-db BACKUP_FILE=~/.forgeops/backups/forgeops-backup-<timestamp>.dump
```

### Restoration Safety & Verification Steps:
1. **Target Namespace Isolation:** Restricts restoration strictly to approved disposable namespace `forgeops-dr-lab`. Refuses protected or unknown namespaces.
2. **Destination Pod Discovery:** Discovers target pod strictly by `app=dr-target-db`, verifies owner Deployment is `dr-target-db`, and verifies target Pod UID $\ne$ source Pod UID.
3. **Target Database Freshness Check:** Queries `information_schema.tables`. Aborts immediately if `accounts`, `projects`, `tasks`, or `flyway_schema_history` already exist.
4. **Strict Error Handling in `pg_restore`:** Invokes `pg_restore --exit-on-error` with zero error suppression (no `|| true`, no `--clean`, no `--if-exists`). Captures exit code; aborts if non-zero.
5. **Authentic Flyway Schema Validation:** Invokes `FlywayMigrationRunner validate` to confirm schema checksums match classpath migrations without fabricated checksums (`12345678` explicitly rejected).
6. **Row Count Audit:** Asserts minimum baselines with `psql -v ON_ERROR_STOP=1`:
   - `accounts`: $\ge 2$ rows
   - `projects`: $\ge 2$ rows
   - `tasks`: $\ge 4$ rows
7. **Relational Integrity Audit:**
   - Asserts 0 orphaned projects (`owner_id` not found in `accounts`).
   - Asserts 0 orphaned tasks (`project_id` not found in `projects`).
8. **Constraint Validation:** Asserts all task statuses conform to `'TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE'`.
9. **Separate Metric Reporting:** Reports `RESTORE_DURATION_MS` (pg_restore only) and `BACKUP_AGE_SECONDS` (backup data age) as distinct metrics.
10. **Archive Preservation:** Asserts original backup archive remains intact and unmutated.

---

## 6. End-to-End Disaster Recovery Drill (Rehearsal)

To rehearse the full disaster recovery lifecycle from end-to-end:

```bash
# Execute full DR drill:
./scripts/cluster/dr/rehearse-dr.sh --target-namespace forgeops-dr-lab

# Makefile shortcut:
make dr-test
```

### Workflow Order:
1. **Lab Provisioning (`setup-dr-lab.sh`):**
   - Generates ephemeral credentials and creates `dr-db-secret` **before** Deployments.
   - Deploys `dr-source-db` and `dr-target-db` with `emptyDir` ephemeral storage (0 PVCs).
   - Verifies authentication on both instances.
   - Initializes `dr-source-db` using authentic Flyway migration runner.
   - Seeds synthetic dataset into source database.
2. **Backup Creation (`backup-db.sh`):** Creates custom format archive with SHA-256 and JSON manifest.
3. **Verification (`verify-backup.sh`):** Validates checksum, magic header, and TOC catalog.
4. **Database Restoration (`restore-db.sh`):** Restores into `dr-target-db` with strict error handling and schema validation.
5. **Application Deployment:** Deploys `dr-api` only after database restoration is 100% verified.
6. **Application-Level Smoke Tests:**
   - Probes `/actuator/health` (asserts `UP`).
   - Authenticated GET `/api/v1/projects` (asserts synthetic projects).
   - Authenticated GET `/api/v1/projects/{id}/tasks` (asserts synthetic tasks).
   - Negative authentication test (asserts 401 Unauthorized for invalid password).
7. **Metric Reporting:** Reports Dump Duration, Restore Duration, Backup Age, and End-to-End Recovery Duration.
8. **Protected PVC Continuity:** Verifies all 5 protected PVCs remain intact.

---

## 7. Teardown & Cleanup Safety Procedures

When dismantling the disposable lab fixture:

```bash
# Graceful teardown of disposable lab:
./scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab

# Makefile shortcut:
make teardown-dr-lab
```

### Safety Guards Enforced:
- **Namespace Audit:** Targets strictly `forgeops-dr-lab` with labels `forgeops.dev/disposable=true` and `forgeops.dev/environment=dr-lab`.
- **UID Verification:** Checks against recorded namespace UID from `/tmp/forgeops-dr-lab.ns-uid`.
- **Zero PVC Invariant:** Refuses teardown if any PVC exists.
- **Resource Allowlist:** Audits namespace against allowlist (`pods`, `services`, `configmaps`, `secrets`, `serviceaccounts`, `deployments`, `replicasets`, `endpoints`, `endpointslices`). Blocks if unexpected StatefulSets, DaemonSets, Jobs, or Ingresses exist.
- **Backup Archive Preservation:** Confirms host backup archives in `~/.forgeops/backups/` remain completely intact post-teardown.
- **Protected PVC Verification:** Audits all 5 protected baseline PVCs.
