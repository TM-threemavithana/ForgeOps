# ADR-0010: Rollback Strategy and Forward-Compatible Database Migrations

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
In continuous delivery platforms, application deployments will occasionally fail (e.g., bad image, startup crash, functional regression). When Argo CD auto-sync is enabled, executing a manual imperative rollback (such as `helm rollback` or `kubectl rollout undo`) fails because Argo CD's reconciliation loop detects drift against the Git repository and immediately forces the cluster back to the broken desired state.

Furthermore, application rollbacks frequently crash if the database schema was modified by a non-backward-compatible migration (e.g., dropped columns or renamed tables), leaving old application code unable to query the database.

## Options Considered
1. **Imperative Rollbacks (`helm rollback`):** Fails under Argo CD GitOps; creates severe state drift between Git and the live cluster.
2. **Destructive Schema Rollbacks (Automatic `down` migrations):** Highly dangerous in stateful relational databases; risks permanent data loss.
3. **Declarative Git Revert with Expand/Contract Schema Migrations:** All rollbacks occur declaratively by reverting the desired-state Git commit. All database schema migrations follow forward-compatible expand/contract patterns.

## Decision
Adopt **Declarative Git Revert Rollbacks** and **Expand/Contract Schema Migrations**:
1. **Declarative Git Rollback:**
   - Under Argo CD, the only durable rollback mechanism is **reverting the Git commit** that updated the container image digest.
   - Merging the revert PR causes Argo CD to gracefully reconcile the cluster back to the previous known-good image digest.
   - If an emergency manual intervention is required, the operator must first **suspend Argo CD application reconciliation** (`argocd app set --sync-policy manual`), execute the mitigation, and subsequently align Git state before re-enabling auto-sync.
2. **Forward-Compatible Database Migrations:**
   - All Flyway migrations follow the **Expand/Contract Pattern**:
     - *Phase 1 (Expand):* Add new nullable columns or tables; deploy application version that writes to both old and new schemas.
     - *Phase 2 (Migrate Data):* Backfill existing records.
     - *Phase 3 (Contract):* Remove old columns only after the new application version is stable across all environments and rollback is no longer required.
   - Database migrations must remain backward-compatible with the immediately preceding application version to allow safe rollbacks.
3. **Stateful Rollback Drills:**
   - Incident drill DR-02 tests deploying an invalid image digest to `dev`, witnessing `ImagePullBackOff`, and recovering via Git revert within 5 minutes.

## Consequences & Trade-offs
### Positive:
- **Git as Single Source of Truth:** Cluster state never diverges from Git during or after a rollback.
- **Data Safety:** Avoids destructive database rollbacks that could truncate columns or corrupt data.
- **Repeatable SRE Process:** Rollback is an auditable, PR-driven engineering process.

### Negative / Limitations:
- Schema changes require disciplined multi-step migrations rather than single breaking SQL scripts.
- Rollback latency is governed by the time required to merge a Git PR and trigger reconciliation (typically 1–3 minutes).

## Verification Tests
- Rollback drill DR-02 proves that reverting `values-dev.yaml` restores pod readiness without manual `kubectl` intervention.
- Old application code (v1) successfully reads and writes to a database migrated to schema v2 without SQL syntax or column errors.

## Reconsideration Triggers
- Adoption of automated Argo Rollouts with progressive canary traffic analysis and automatic metric-based rollback in advanced phases.
