# Start Here — ForgeOps Antigravity Plan Pack

This pack is a **complete design and implementation blueprint**, **not implemented source code**.

## Files

- `FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md`: canonical detailed architecture, requirements, APIs/data model, Terraform/Ansible/Kubernetes/GitOps/observability/security/recovery designs, 16 gate plan, acceptance tests, runbooks, rubrics and references.
- `AGENTS.md`: safety, resource ownership and review-gated execution instructions for the IDE agent.

## Set up in Antigravity IDE

1. Open an existing or new `forgeops/` Git working directory in Antigravity. Do not overwrite prior work.
2. Save the master plan as `forgeops/docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md`.
3. Save `AGENTS.md` as `forgeops/AGENTS.md`.
4. Ask Antigravity:

   > Read AGENTS.md and docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md. Inspect the existing workspace without overwriting files. Perform safe G00 prerequisites and hardware feasibility review, verify tool compatibility against current official documentation, and produce ADRs, initial SRS, architecture and G00 acceptance evidence. Show me the implementation plan before applying any changes. Do not proceed to G01.

5. Review G00, approve it, and only then implement G01.

## Important distinctions

- All promised technology areas—including **Ansible**, **Terraform**, **Prometheus**, **Grafana**, **Loki**, **Grafana Alloy**, **Alertmanager**, **Kubernetes**, **Helm**, **Argo CD**, and **GitHub Actions**—are deliberately included.
- Optional advanced additions are **Jenkins**, **OpenTelemetry + Tempo**, **Cilium**, **SOPS+age**, policy engines and ingress/TLS. Cilium is **required** before claiming NetworkPolicy enforcement tests.
- The design requires **no paid AWS/Azure/GCP account**. Computer hardware and electricity still cost money.
- Do not claim anything has been built until commands and tests actually run.
