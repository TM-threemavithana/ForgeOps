# Gate G13 Evidence Directory: PostgreSQL Backup, Disaster Recovery & Verification

This directory contains verified execution logs, cluster audits, and acceptance reports for **ForgeOps Gate G13 (Database Backup, Disaster Recovery, and Recovery Evidence)**.

## Contents

- **`G13-acceptance-report.md`**: Canonical acceptance report detailing RTO, RPO, multi-tenant authenticated smoke test outcomes, Flyway checksum verification, cluster continuity, and runbook cross-references.
- **`dr-rehearsal.log`**: Unabridged, timestamped live execution log from `scripts/cluster/dr/rehearse-dr.sh` covering lab provisioning, Flyway migrations, synthetic data seeding, pg_dump custom archive backup, SHA-256 verification, fresh-instance pg_restore, ForgeTasks API rollout, authenticated REST smoke tests, teardown, and protected PVC validation.
- **`cluster-inventory.txt`**: Post-rehearsal snapshot of all Kubernetes workloads, services, secrets, and configurations verifying zero residual resources in the disposable lab namespace.
- **`pvc-continuity.txt`**: Cryptographic and UID verification of all 5 pre-existing protected PersistentVolumeClaims across `forgeops-dev`, `forgeops-gitops-rehearsal`, and `forgeops-observability`.

## Key Measured Metrics

| Metric | Measured Value | Requirement / Target | Status |
|:---|:---|:---|:---|
| **pg_dump Duration** | 273 ms | Sub-minute | PASSED |
| **pg_restore Duration (RTO)** | 252 ms | < 5 minutes | PASSED |
| **Backup Age / Freshness (RPO)** | 12 seconds | < 1 hour | PASSED |
| **End-to-End Recovery Time** | 89.29 seconds | < 10 minutes | PASSED |
| **Protected PVC UIDs Preserved** | 5 / 5 (100%) | 100% Intact | PASSED |
| **Disposable Lab PVC Leaks** | 0 PVCs | 0 PVCs (`emptyDir: {}`) | PASSED |
| **Multi-Tenant REST Smoke Tests** | 100% Passed | Project & Task retrieval + 401 guard | PASSED |

