# ForgeOps Gate G08 — Declarative GitOps Architecture (Argo CD)

This directory documents the declarative **Argo CD Application and AppProject Architecture** for ForgeOps in accordance with `ADR-0003`, `ADR-0004`, and `ADR-0014`.

## Current G08 Rehearsal State

The G08 rehearsal has been deployed and verified on the local
Kind cluster. The original Phase 2 safeguards below describe
the earlier design and the inactive development/staging examples.

The active rehearsal uses:

- Application: `forgetasks-rehearsal`
- Project: `forgeops-rehearsal-project`
- Destination: `forgeops-gitops-rehearsal`
- Source branch: `g08-argocd-gitops`
- Automated synchronization: enabled
- Self-healing: enabled
- Automatic pruning: disabled
- Allow-empty synchronization: disabled
- Automatic namespace creation: disabled
- Secret management through Argo CD: prohibited

The rehearsal API and PostgreSQL database use isolated
resources. No Argo CD Application currently adopts the
protected G06 namespace or the staging namespace.

Validated acceptance evidence is recorded in
`docs/evidence/G08/readiness.md`.

The active manifest files are:

- `apps/forgetasks-rehearsal.yaml`
- `projects/forgeops-rehearsal-project.yaml`
- `../charts/forgetasks/values-rehearsal.yaml`

The `.yaml.example` manifests remain inactive examples.

Do not delete the G08 branch while the live Application
still targets it. A controlled transition to `master`
is required after the changes have been reviewed and merged.

## 1. Historical Architectural Safeguards (Phase 2 Baseline)

In accordance with G08 Phase 2 architecture decisions:
1. **Zero Active Workload Targeting:**
   No Argo CD Application is active or installed targeting `forgeops-dev` or `forgeops-staging`. The example manifests in `projects/` and `apps/` carry `.example` extensions to prevent accidental deployment or automatic adoption.
2. **Conservative Sync Policy:**
   The initial adoption design disabled automatic reconciliation. The active G08 rehearsal now has automated synchronization and self-healing enabled, while automatic pruning remains disabled.
3. **No Force or Replace:**
   Neither `Replace=true` nor `Force=true` sync options are permitted. Destructive adoption is prohibited.
4. **Out-of-Band Secrets Boundary:**
   Kubernetes Secrets (`forgetasks-db-secret`) are blacklisted in `AppProject` (`forgeops-project.yaml.example`). Argo CD never creates, templates, or modifies secrets.
5. **G06 Workload Isolation:**
   All G06 workloads in `forgeops-dev` and the database PVC `postgres-storage-forgetasks-db-0` remain under G06 manifest ownership until an isolated rehearsal has proven the adoption path safe.

## 2. Directory Structure

```text
platform/argocd/
├── README.md                                # This architecture document
├── projects/
│   └── forgeops-project.yaml.example        # AppProject defining repository and namespace boundaries
└── apps/
    ├── forgetasks-dev.yaml.example          # Non-active Dev Application definition
    └── forgetasks-staging.yaml.example      # Non-active Staging Application definition
```

## 3. G06 Adoption & Migration Strategy (Future Phase 4)

Because `spec.selector` is immutable on Deployments and StatefulSets in Kubernetes, and the G06 manifests have different selector labels than the G07 Helm chart, direct adoption without recreation will fail.

The proposed adoption procedure requires:
1. Complete `pg_dump` backup of `forgeops-dev` database stored in `~/.config/forgeops/backups/`.
2. Isolated dry-run rehearsal in a scratch namespace (e.g., `forgeops-adoption-drill`).
3. Only upon successful rehearsal, a controlled orphan retirement of G06 stateless resources followed by Argo CD adoption while preserving the PVC `postgres-storage-forgetasks-db-0`.
