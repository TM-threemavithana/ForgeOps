# G08 — Argo CD GitOps Readiness and Acceptance Evidence

## Status

**Functional acceptance: PASSED**

Gate G08 establishes Terraform-managed Argo CD infrastructure and
an isolated GitOps rehearsal for the ForgeTasks application.

Evidence was collected on 2026-10-26 from the local Kind cluster,
WSL Git checkout, and Argo CD Application status.

This report documents observed results. It is not authorization
to migrate G06 workloads, destroy infrastructure, or delete the
G08 feature branch.

## 1. Scope and Ownership

- Kubernetes context: `kind-forgeops`
- Argo CD namespace: `argocd`
- Rehearsal namespace: `forgeops-gitops-rehearsal`
- Protected G06 namespace: `forgeops-dev`
- Staging namespace: `forgeops-staging`
- Argo CD Application: `forgetasks-rehearsal`
- AppProject: `forgeops-rehearsal-project`
- Git source: `TM-threemavithana/ForgeOps`
- GitOps source branch: `g08-argocd-gitops`

Terraform manages the Argo CD bootstrap, not the existing
G06 application workloads or PostgreSQL PVC.

The rehearsal deployment uses a dedicated namespace,
database Secret, PostgreSQL StatefulSet, and PVC.

## 2. GitOps Acceptance Results

| Test | Observed result | Status |
|---|---|---|
| Terraform Argo CD bootstrap | Argo CD installed and healthy | PASS |
| Isolated Helm rehearsal deployment | API and database Ready | PASS |
| API readiness | HTTP 200 | PASS |
| Database account creation | HTTP 201 | PASS |
| Duplicate account protection | HTTP 409 | PASS |
| Manual Git-driven API CPU update | Deployment reconciled | PASS |
| Automatic Git synchronization | Automated operation succeeded | PASS |
| Self-healing drift recovery | CPU restored from 250m to 200m | PASS |
| Automatic Git-revert recovery | CPU restored from 250m to 200m | PASS |
| Database continuity after recovery | Existing account returned HTTP 409 | PASS |
| Final Argo CD health | Synced / Healthy | PASS |
| Rehearsal database PVC retention | Original PV remained Bound | PASS |
| Protected G06 isolation | API and database Ready; original PV retained | PASS |

## 3. Declarative Recovery Evidence

Reversible test commit:

`008f5ccc7fb2eb25ccc37e4a94660b028d51d106`

This commit changed the rehearsal API CPU request from
`200m` to `250m`.

Argo CD automatically applied this revision. The new API
Deployment successfully rolled out and became healthy.

Recovery commit:

`a37d298589f2a00c2b3e21698f2f7d0b7a7eb7f4`

This commit reverted only the test CPU change.

Argo CD automatically applied the revert:

- Resolved Git revision matched the recovery commit.
- Applied Git revision matched the recovery commit.
- Synchronization operation: `Succeeded`
- Automated operation: `true`
- Restored live CPU request: `200m`
- Final Application status: `Synced / Healthy`

No manual Argo CD synchronization or direct Kubernetes patch
was used to apply the Git revert.

## 4. Persistent Storage Safety

Rehearsal PostgreSQL:

- PVC: `postgres-storage-forgetasks-rehearsal-db-0`
- Persistent volume:
  `pvc-b5ea8ec9-47e8-4979-afdb-621f2e3c63b8`
- Final state: Bound

Protected G06 PostgreSQL:

- PVC: `postgres-storage-forgetasks-db-0`
- Persistent volume:
  `pvc-84853fb3-4d13-43a9-bc62-973c3be3c90c`
- Final state: Bound

The recorded database-continuity test used an existing
rehearsal account and received HTTP 409 after recovery.

No deliberate database deletion, PVC recreation, or G06
workload adoption occurred during these drills.

## 5. Security and Isolation

The live AppProject was verified to restrict deployment
to the rehearsal namespace and designated Git repository.

Verified policy:

- Cluster-scoped resource whitelist: empty
- Kubernetes Secret resources: blacklisted
- Automatic synchronization: enabled
- Self-healing: enabled
- Automatic pruning: disabled
- Allow-empty synchronization: disabled
- Automatic namespace creation: disabled

The rehearsal database Secret is provisioned out of band.

The secret-injection script uses a dedicated credential source,
fixed context and namespace, restrictive file-permission checks,
and create-only Secret provisioning.

## 6. Static Validation

The following checks passed:

- Git whitespace validation
- Terraform formatting
- Secret-injection script Bash syntax
- Helm chart lint
- Git branch and clean working-tree verification

The Terraform state, local environment files, and Terraform
working directory are covered by Git ignore rules.

## 7. Observations and Limitations

### API startup

The restored API Pod experienced one startup-probe-triggered
container restart. Kubernetes reported exit code 143.

The API subsequently passed readiness, the Deployment
completed its rollout, and Argo CD reported Healthy.

Further probe tuning should be based on additional evidence.

### Repository comparison

One temporary Argo CD repository comparison failure was
observed during the revert drill.

A subsequent automatic reconciliation succeeded and applied
the intended recovery commit.

### Secret provisioning

The injector's create-only policy does not make the Kubernetes
Secret intrinsically immutable.

The validation-only mode checks local credential hygiene but
does not validate the live Kubernetes target.

Secret creation and governance labeling are separate operations.

### Scope limitation

Successful database continuity testing does not constitute a
full database disaster-recovery or backup-restoration test.

## 8. Merge and Cleanup Verification

G08 implementation and GitOps master transition
were completed through two merged pull requests.

- Implementation PR: #22
- Implementation merge: f47ef2d
- Master-transition PR: #23
- Master-transition merge: 494883cd
- Live Application targetRevision: master
- Argo CD synchronization: Synced
- Argo CD health: Healthy

The live Application was updated using the
merged declarative Application manifest.

The deployed Helm chart was verified unchanged
between the original G08 feature branch and master.

No Terraform destroy, namespace deletion,
PVC recreation, or protected G06 workload
adoption was performed during this transition.

The original feature branch may be retained
until a separate cleanup decision is approved.

## 9. Final Acceptance Conclusion

G08 runtime acceptance: PASS

Verification date: 2026-10-27

### GitOps

- Live targetRevision: master
- Live Git revision:
  494883cd223fd39d5fcac7555f1f288908889739
- Sync status: Synced
- Health status: Healthy
- Automatic pruning remains disabled.

### Rehearsal Workloads

- API Deployment: 1/1 ready
- PostgreSQL StatefulSet: 1/1 ready
- API rollout: successful
- PostgreSQL rollout: successful
- Rehearsal PVC: Bound

### Protected G06 Workloads

- API Deployment: 1/1 ready
- PostgreSQL StatefulSet: 1/1 ready
- Protected database PVC: Bound

### Persistent Storage Continuity

G08 rehearsal PVC UID:
b5ea8ec9-47e8-4979-afdb-621f2e3c63b8

Protected G06 PVC UID:
84853fb3-4d13-43a9-bc62-973c3be3c90c

Both PVC identities were verified unchanged
after the GitOps master transition.

### Remaining Limitations

The operational limitations documented in
Section 7 remain applicable.

In particular, create-only Secret provisioning
does not enforce Secret immutability, and full
database disaster recovery was not tested.

G08 implementation and runtime verification
are complete.

Formal documentation closure is subject to
review and merge of this evidence update.
