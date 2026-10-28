# ForgeOps SRE Specification — Database Backup & Disaster Recovery (G13)

**Document Version:** `1.1.0`  
**Gate:** G13 — PostgreSQL Backup, Recovery Automation, Disaster Recovery Testing  
**Status:** Approved Specification  

---

## 1. Overview & Architectural Boundaries

This specification defines the reliability standards, Service Level Objectives (SLOs), Service Level Indicators (SLIs), storage architecture, and data integrity guarantees for PostgreSQL database backups and disaster recovery within the ForgeOps platform.

The implementation operates strictly under the **Local-First, Zero-Paid-Cloud** architecture, using native PostgreSQL 16 custom format (`-Fc`) archives, cryptographic checksum verification, authentic Flyway schema validation, and isolated disposable recovery environments.

---

## 2. Disaster Recovery Service Level Objectives (SLOs)

| Metric | SLO Target (Lab Context) | Measured SLI Definition | Enforcement Mechanism |
|:---|:---|:---|:---|
| **Recovery Time Objective (RTO)** | $\le 15$ minutes | Elapsed time from `restore-db.sh` invocation to complete database readiness and verified record queries. | Automated measurement logged in restore report (`RESTORE_DURATION_MS`). |
| **End-to-End Recovery Time** | $\le 15$ minutes | Total elapsed time from disaster rehearsal start to restored API healthy and verified. | Automated measurement logged in rehearsal report (`E2E_DURATION_MS`). |
| **Recovery Point Objective (RPO)** | $\le 24$ hours (scheduled)<br>$\le 5$ minutes (on-demand) | Data age: difference between current restoration timestamp and `backup_epoch_seconds` from manifest. | Automated calculation in `restore-db.sh` (`BACKUP_AGE_SECONDS`). |
| **Backup Integrity** | **100%** | Fraction of generated backups where live SHA-256 and TOC match manifest without error. | `verify-backup.sh` pre-restoration gate. |
| **Schema Integrity** | **100% Authentic** | Post-restore schema checksum matches genuine Flyway migrations without fabricated checksums. | `FlywayMigrationRunner validate` execution. |
| **Relational Consistency** | **0 Errors (100%)** | Zero foreign key orphans in restored schema (`accounts` $\rightarrow$ `projects` $\rightarrow$ `tasks`). | Post-restore SQL assertion queries (`ON_ERROR_STOP=1`). |
| **Constraint Validity** | **0 Violations** | Zero invalid values violating domain check constraints (`chk_tasks_status`, `chk_tasks_priority`). | Post-restore SQL constraint checks (`ON_ERROR_STOP=1`). |

---

## 3. Backup Archive Specification

### Format: PostgreSQL Custom Archive (`pg_dump -Fc`)
- **Engine Version:** Pinned to PostgreSQL 16 client and server compatibility.
- **Compression:** Native zlib compression embedded within custom archive format.
- **Magic Header:** Validated against standard `PGDMP` 5-byte header.
- **Contents:** Complete schema DDL, table data, sequences, foreign key constraints, and Flyway migration metadata (`flyway_schema_history`).

### Manifest Schema (`*.manifest.json`)
Every backup archive must be accompanied by an immutable manifest file generated at creation time:

```json
{
  "manifest_schema_version": "1.0",
  "backup_format": "pg_dump_custom_v1",
  "backup_file": "forgeops-backup-forgeops-dr-lab-forgetasks-20261028-120000Z.dump",
  "source_namespace": "forgeops-dr-lab",
  "source_database": "forgetasks",
  "source_db_user": "forgeuser",
  "source_pg_version": "16.x",
  "pg_dump_version": "pg_dump (PostgreSQL) 16.15",
  "backup_utc_timestamp": "20261028-120000Z",
  "backup_epoch_seconds": 1793188800,
  "dump_duration_ms": 1250,
  "archive_size_bytes": 18432,
  "sha256_checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "tables_catalog": [
    "accounts",
    "flyway_schema_history",
    "projects",
    "tasks"
  ],
  "immutable": true
}
```

---

## 4. Storage, Retention & Security Boundaries

1. **Storage Location:**  
   Backups must be written to a dedicated directory outside the Git repository:
   - Default: `~/.forgeops/backups/` (configurable via `FORGEOPS_BACKUP_DIR`).
   - Backup files (`*.dump`) and manifests (`*.manifest.json`) are strictly excluded from Git via `.gitignore`.
2. **Restrictive File Permissions:**  
   - Directory: `chmod 0700`
   - Archive files & manifests: `chmod 0600` (read/write by owner only; no world or group access).
3. **Retention Policy:**  
   - Retain last 7 daily snapshots.
   - Retain last 4 weekly snapshots.
   - Prune expired archives only after verifying at least 1 recent valid backup exists.
4. **Encryption Policy & Physical Single-Laptop Risk:**  
   > [!WARNING]
   > **Physical Co-location Risk:**  
   > In this local lab environment, backup archives reside on the same physical NVMe drive as the Kind cluster virtual disk. This protects against logical database corruption or accidental namespace deletion, but **does not protect against physical host drive failure, workstation theft, or catastrophic hardware loss**.  
   > **Encryption Status:** Lab backups are currently stored unencrypted on the local filesystem. In an enterprise production deployment, offsite replication to cloud object storage (e.g., AWS S3 or GCP Cloud Storage) with client-side envelope encryption (via `age` or Cloud KMS) and Object Lock (WORM) is mandatory.

---

## 5. Tool Verification Note: `pg_verifybackup`

Upstream PostgreSQL provides `pg_verifybackup` specifically for physical base backups produced by `pg_basebackup` (validating WAL records and manifest checksums of raw data directories).

Because ForgeOps utilizes logical custom archives (`pg_dump -Fc`), `pg_verifybackup` is architecturally inapplicable. Archive integrity is verified via cryptographic SHA-256 matching and `pg_restore -l` TOC parsing, ensuring full logical consistency without tool misapplication.

---

## 6. Target Isolation, Credential Race Prevention & Flyway Authenticity

1. **Credential Race Prevention:** Ephemeral database credentials and the Kubernetes Secret `dr-db-secret` are provisioned *before* PostgreSQL Deployments are applied.
2. **Target Isolation:** Restoration is strictly restricted to `forgeops-dr-lab` with verified `app=dr-target-db` pod ownership. Source and destination Pod UIDs must differ.
3. **Target Freshness Enforcement:** Target database must contain zero pre-existing application tables prior to restoration. Restoration into a populated database is rejected.
4. **Authentic Flyway History:** Schema is initialized and validated using the genuine Flyway migration runner (`FlywayMigrationRunner`), verifying the exact migration version, description, execution record, and authentic checksum (`-308033445`). Fabricated checksums (`12345678`) are strictly rejected.
5. **Post-Restore Smoke Testing:** `dr-api` is deployed strictly after database restoration and verification. REST queries authenticate against `/api/v1/projects` and `/api/v1/projects/{projectId}/tasks` with positive and negative authentication checks.
