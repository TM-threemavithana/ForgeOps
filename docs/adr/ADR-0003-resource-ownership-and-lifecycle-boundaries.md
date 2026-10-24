# ADR-0003: Strict Resource Ownership and Lifecycle Boundaries

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
When multiple automation tools (Terraform, Ansible, Helm, Argo CD, Shell scripts, Docker CLI) operate within the same infrastructure environment without strict boundaries, resource ownership collisions inevitably occur. Common failure modes include:
- Terraform and Argo CD competing to mutate the same Kubernetes manifests.
- Docker prune destroying volumes managed by Kubernetes StatefulSets.
- Ansible attempting to reconfigure containers inside Kind nodes.
- Terraform managing the Kind cluster lifecycle, causing state deadlocks.

## Options Considered
1. **Terraform Owns Everything:** Use Terraform Kubernetes and Helm providers to manage Kind, Argo CD, and all application workloads. Leads to massive state files, slow planning, and violates GitOps pull-based principles.
2. **Argo CD Owns Everything:** Cannot provision physical Docker networks, local VMs, or the initial Kubernetes cluster itself.
3. **Strict Separation of Concerns (Sole Owner Contract):** Each tool is assigned an exclusive, non-overlapping domain of responsibility.

## Decision
Enforce a **Strict Sole Owner Contract** across all infrastructure and workload components:

| Resource Domain | Sole Owner | Explicitly Forbidden Overlapping Owner |
|---|---|---|
| **Kind Cluster Containers & Nodes** | Explicit Shell Lifecycle (`scripts/cluster/create.sh`) | Terraform Docker provider / manual Docker prune |
| **Local Diagnostic Lab Fixture** | Terraform `local-docker-lab` module | Docker Compose / Kind / manual writes |
| **Linux Guest OS, SSH, Nginx** | Ansible Playbooks & Roles | Terraform `remote-exec` / ad-hoc SSH edits |
| **Cluster Platform Bootstrap (Argo CD)** | Terraform `cluster-bootstrap` module | Argo CD self-management before approved handoff |
| **Application & Observability Deployments** | Argo CD (rendering Helm charts) | Direct `helm upgrade` / Terraform Kubernetes provider |
| **Database Schema & Data** | Flyway + PostgreSQL Engine | Terraform / Helm destructive resets |
| **Operator Secrets** | Out-of-band local injection (`~/.config/forgeops/`) | Git repository / Terraform state / Helm values |

## Consequences & Trade-offs
### Positive:
- **No Drift Wars:** Reconcilers do not fight over the same resource definitions.
- **Predictable Blast Radius:** Deleting a Terraform lab fixture never touches Kind or Docker Compose.
- **Clean GitOps Model:** Argo CD reconciles desired state from Git without interference from manual Helm commands.

### Negative / Limitations:
- Multi-step bootstrapping is required: Cluster created by script → Argo CD installed by Terraform → Application synced by Argo CD.
- Operators cannot use quick `helm install` commands in the Argo CD-managed namespaces.

## Verification Tests
- `terraform plan` in `local-docker-lab` detects zero drift when Kind or Compose workloads change.
- `terraform destroy` in `local-docker-lab` tears down only the diagnostic fixture, leaving Kind nodes and networks intact.
- Argo CD auto-sync reconciles out-of-band mutations made to `forgetasks-api` Deployments.

## Reconsideration Triggers
- Adoption of Crossplane or Cluster API if migrating from Kind to managed cloud infrastructure.
