# ForgeOps Agent Operating Rules

Read `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` before planning or editing. It is the canonical scope and acceptance source. This folder currently contains a **plan only**, not a functioning application.

## Hard boundaries

1. **Zero paid cloud dependency**: no AWS/Azure/GCP/VPS or credit-card request.
2. **Review-driven implementation**: do not implement more than one gate G00–G15 per reviewed change.
3. **Single owner per resource**: kind shell lifecycle owns cluster, Terraform owns its own local fixture and Argo bootstrap, Ansible owns independent Linux guest configuration, Argo CD owns app and observability K8s workloads.
4. **Protect user machine**: never run `docker system prune -a`, arbitrary `terraform destroy`, raw `rm -rf`, broad firewall changes, destructive Git commands, or delete unscoped Kubernetes objects. Confirm explicit target and backup before every destructive lab change.
5. **No secret leaks**: do not commit state, kubeconfigs, `.env.local`, SSH private keys, backup data, tokens or secret values. Redact command logs and evidence.
6. **Verify version compatibility**: use current official docs, pin versions/images/actions after review; no blind `latest` in deployable configurations.
7. **No fake successes**: if a command cannot run, mark Blocked or Not Run. Never fabricate screenshots, tests, release digests, dashboards or telemetry.
8. **Hardware-aware**: choose Core/Extended/Capstone profile and run resource-heavy components sequentially when needed.
9. **App security**: no Internet-facing dashboards, DB, Argo CD or guest SSH; bind loopback or restricted host-only lab networks.
10. **Actual Ansible**: control Linux Ubuntu guest via SSH. A Docker-only simulation cannot be presented as a separate VM.

## Standard gate workflow

1. Print scope of selected gate and inspect `git status`, existing files, docs and earlier gate evidence.
2. Present planned edits, rationale, acceptance tests, permissions needed, rollback and resource impact.
3. Wait for approval when action is destructive or privilege-bearing; default to safe non-destructive discovery.
4. Implement minimal changes and tests for that gate only.
5. Run commands if tooling is available; log command/version/exit status/result without secrets.
6. Update requirement-to-test traceability, compatible versions, decisions and risk register.
7. End with **Passed / Passed with limitation / Failed / Blocked**; links to tangible evidence and next recommended gate.

## First action

Do **G00 preflight and architecture review only**, not project-wide implementation. Validate Windows/WSL2, Docker, hardware, disk, VM feasibility, connectivity, potential costs, tool versions, resource ownership and stage boundaries. Produce ADRs and reviewed G00 readiness report. Do not invent a working ForgeOps codebase.
