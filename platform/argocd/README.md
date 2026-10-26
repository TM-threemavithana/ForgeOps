# ForgeOps Gate G08 — Declarative GitOps Architecture (Argo CD)

This directory documents the declarative **Argo CD Application and AppProject Architecture** for ForgeOps in accordance with `ADR-0003`, `ADR-0004`, and `ADR-0014`.

## 1. Architectural Safeguards (Phase 2 Baseline)

In accordance with G08 Phase 2 architecture decisions:
1. **Zero Active Workload Targeting:**
   No Argo CD Application is active or installed targeting `forgeops-dev` or `forgeops-staging`. The example manifests in `projects/` and `apps/` carry `.example` extensions to prevent accidental deployment or automatic adoption.
2. **Conservative Sync Policy:**
   Automated synchronization (`syncPolicy.automated`), automated self-healing (`selfHeal: true`), and automated resource pruning (`prune: true`) are **strictly disabled** for the initial adoption stage.
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
