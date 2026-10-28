# ForgeOps Runbook — PostgreSQL Disaster Recovery & Database Restoration

**Document ID:** `RB-DR-001`  
**Target Workload:** ForgeTasks PostgreSQL 16 Database  
**Author:** ForgeOps Platform & Reliability Engineering  
**Classification:** Operational Runbook — Gate G13  

---

## 1. Overview & Objectives

This runbook defines the emergency operational procedures for backing up, verifying, and recovering the ForgeTasks PostgreSQL database under partial data corruption, container failure, or disaster scenarios.

### Disaster Recovery Targets (Lab Baseline)
- **Recovery Time Objective (RTO):** Target $\le 15$ minutes from incident declaration to verified API traffic resumption. (Observed lab recovery duration: $< 5$ seconds).
- **Recovery Point Objective (RPO):** Target $\le 24$ hours for scheduled daily snapshots; $\le 5$ minutes for on-demand pre-maintenance snapshots. (Observed lab data age: $< 2$ minutes).

---

## 2. Fundamental Safety Constraints

> [!CAUTION]
> **Zero Overwrite Invariant:**  
> Never run `pg_restore` directly over an active, existing database without first establishing a pre-cutover backup.  
> Under no circumstances may restoration overwrite or target `forgeops-dev` or `forgeops-gitops-rehearsal` without explicit, reviewed operator override and secondary approval.

1. **Verify Before Restoring:** Always validate the backup archive's cryptographic SHA-256 checksum and Table of Contents (TOC) using `verify-backup.sh` prior to initiating restoration.
2. **Scratch Database First:** Always restore into a fresh, isolated database instance (e.g., in `forgeops-dr-lab`) to verify relational integrity, schema migrations, and row counts before performing any application traffic cutover.
3. **No Secret Leaking:** Never echo, log, or persist database passwords in shell history, logs, or unencrypted text files. Use memory-only variables loaded directly from Kubernetes Secrets.
4. **Preserve Backup Files:** Never delete or overwrite the original backup dump file during restoration or cleanup.

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
2. Checks filesystem headroom on the destination directory (requires $\ge 250$ MB free).
3. Connects securely via local port-forward or pod tunnel using memory-only credentials from `forgetasks-db-secret`.
4. Executes `pg_dump -Fc -b -v` to a temporary `.tmp` file.
5. Verifies archive readability using `pg_restore -l`.
6. Atomically renames the file to:
   `forgeops-backup-${SOURCE_NS}-${DB_NAME}-${TIMESTAMP}.dump`
7. Computes SHA-256 cryptographic checksum and file size.
8. Generates an immutable manifest file (`.manifest.json`) capturing source database metadata, UTC timestamp, epoch seconds, tool versions, and table catalog.
9. Sets restrictive filesystem permissions (`chmod 0600`).

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

### Verification Steps Executed Post-Restore:
1. **Flyway Migration Status:** Queries `flyway_schema_history` to verify successful migrations exist (`success=true`).
2. **Row Count Audit:** Asserts minimum baselines across all restored tables:
   - `accounts`: $\ge 2$ rows
   - `projects`: $\ge 2$ rows
   - `tasks`: $\ge 4$ rows
3. **Relational Integrity Audit:**
   - Asserts 0 orphaned projects (`owner_id` not found in `accounts`).
   - Asserts 0 orphaned tasks (`project_id` not found in `projects`).
4. **Constraint Validation:** Asserts all task statuses conform to `'TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE'`.
5. **RTO & RPO Measurement:** Records exact restoration elapsed time (ms) and data age (seconds).
6. **Archive Preservation:** Asserts original backup archive remains intact and unmutated.

---

## 6. End-to-End Disaster Recovery Drill (Rehearsal)

To rehearse the full disaster recovery lifecycle from end-to-end:

```bash
# Execute full DR drill:
./scripts/cluster/dr/rehearse-dr.sh --target-namespace forgeops-dr-lab

# Makefile shortcut:
make dr-test
```

This automates:
1. Synthetic lab environment provisioning (`setup-dr-lab.sh`).
2. Source database backup creation (`backup-db.sh`).
3. Cryptographic and TOC verification (`verify-backup.sh`).
4. Scratch database restoration (`restore-db.sh`).
5. Application smoke test via ForgeTasks API `/actuator/health` and `/api/projects`.
6. Metrics calculation (RTO, RPO, record verification).
7. Protected PVC baseline continuity audit.
