# ForgeOps — Master Implementation Plan

**Version:** 1.0 · **Date:** 2026-10-19 · **Status:** Complete draft implementation specification, awaiting review; **not implemented or tested**  
**Audience:** Engineer building in Antigravity IDE; technical reviewers and potential employers  
**Purpose:** An executable, review-gated blueprint for a **zero-mandatory-cloud-cost**, self-hosted DevOps, Platform Engineering, and SRE portfolio system.

> **Read this first.** Nothing in this document asserts the repository, infrastructure, tests, or demos already exist. Commands under "planned interface" describe commands **to implement**. Never report a successful gate unless the command ran and its evidence was captured. Never apply destructive commands to resources outside the ForgeOps sandbox.

## Executive decision

ForgeOps will operate a *real, small Java application* through a full engineering delivery lifecycle: code → automated tests → trusted image → controlled GitOps promotion → local Kubernetes deployment → metrics/logs/alerts → tested rollback and database recovery. A separate Linux VM will demonstrate **Ansible**, and independently owned local resources will demonstrate **Terraform**. The implementation is deliberately divided into **Core**, **Extended**, and **Capstone** profiles so a learner does not need to run everything concurrently or pay for AWS.

### Required outcomes

1. A reproducible local development path that starts with Docker Compose and works with **no cloud account**.
2. A GitHub-hosted CI pipeline for tests, static checks, container builds and publishing to GitHub Container Registry (GHCR), plus a local/offline alternative for critical steps.
3. An **actual Ansible-managed Linux guest** reachable over SSH, with idempotent roles, inventory, templating, handlers, least-privilege administration and check-mode verification.
4. **Terraform** provisioned local Docker infrastructure, with explicit state protection, modules, planning, drift detection and controlled destruction.
5. A local **kind** Kubernetes cluster running both `dev` and `staging` namespaces with Helm and GitOps-driven deployments through **Argo CD**.
6. **Prometheus + Grafana + Alertmanager** covering application and platform metrics, with **Loki + Grafana Alloy** covering logs; optional OpenTelemetry + Tempo for traces.
7. A reproducible threat model, non-root containers, dependency/image/secret scanning, least-privilege Kubernetes RBAC, supported NetworkPolicy enforcement and no leaked credentials.
8. Load tests, deliberate failure injections, incident response runbooks, measured backup and restore, rollout recovery, technical architecture rationale and credible portfolio evidence.

### Deliberate non-goals / truthfulness boundaries

- No AWS, Azure, GCP, paid VPS, credit card, custom domain or commercial monitoring service is required.
- **Not** a claim of multi-datacenter availability, true cloud experience, proven production security certification, real customer traffic or SLA guarantees.
- **Not** an unnecessary mesh of microservices: one modular Spring Boot service plus PostgreSQL is sufficient to demonstrate operational engineering.
- **Not** a fully offline first bootstrap: initial tool and container-image downloads require internet. The application itself has a documented offline operation path once necessary tools and images are available locally.
- No production data or real personal secrets are used in the lab.

---

## 1. Learning goals, scope and proof

### Skills-to-evidence matrix

| Competency | Real component | Evidence expected |
|---|---|---|
| Linux and networking | Ubuntu guest + WSL2 host; SSH, ports, DNS, firewall | Command transcript, topology diagram, incident diagnosis |
| Java delivery | Spring Boot + PostgreSQL + Flyway | Passing unit/integration tests, API examples |
| Source control | Git PRs, protected main, versioned releases | PR review history and release notes |
| CI | GitHub Actions and local `make ci` | Red-to-green CI proof, coverage and scan results |
| Containers | Docker, Compose, GHCR | Dockerfile, image digest, SBOM, non-root proof |
| Terraform | Docker provider and isolated local services | `fmt`, `validate`, `plan`, approved `apply`, drift demo |
| Ansible | Linux guest via SSH | Roles, idempotent second run, lint and check mode |
| Kubernetes | kind, Deployment/Service/PVC/Jobs/NetworkPolicies | `kubectl` status, injected-failure test |
| CD / GitOps | Helm + Argo CD | Approved image-digest commit → sync → smoke tests |
| Monitoring | Prometheus, Grafana, Alertmanager | Dashboard screenshots, queries, firing/resolved alert |
| Logs | Grafana Alloy, Loki | Query filtered by service, namespace, request ID |
| Security | Trivy, Gitleaks, RBAC, runtime restrictions | Scanner reports and blocked-action tests |
| Reliability | k6, rollback, database backup and restore | Measured RTO/RPO exercise, incident report |
| Documentation | ADRs, SRS, runbooks, diagram, demo | Reproducibility run by fresh reviewer |

### Quality principles

- **One resource = one owner:** Terraform owns its own local Docker resources and a limited set of **platform bootstrap** objects; Ansible owns the guest OS; Argo CD owns GitOps applications; Helm renders manifests rather than mutating independently after Argo takes ownership. `kind` is created by an explicit lifecycle script, **not** simultaneously by Terraform.
- **Separation:** the Ansible target guest is independent of kind; a GitHub runner **never** requires access into a laptop/cluster.
- **Safe defaults:** bind local UIs to loopback; least privilege, no unreviewed automatic prune on stateful environments, never check plaintext credentials or Terraform state into Git.
- **Reproducible evidence:** pin versions *after validation*, use a compatibility matrix, write acceptance tests and capture exact machine conditions. A green UI screenshot alone is insufficient.
- **Incremental learning:** complete each gate, document a trade-off and demonstrate an intentional failure before starting the next technology.

---

## 2. Hardware, prerequisites and execution profiles

**Primary host:** Windows 10/11 with WSL2 Ubuntu and Docker Engine through Docker Desktop's WSL integration for qualifying personal/education use, or an appropriately configured Linux-native Docker Engine alternative. Store the repo inside the WSL Linux filesystem for better filesystem behavior than mounted Windows directories. Check the current Docker Desktop license before installation; free personal/education use is conditional.

| Profile | Practical host guidance* | What runs together | Deferred components |
|---|---|---|---|
| **Core** | 8 GB RAM, ideally ≥40 GB free SSD | Spring API + PostgreSQL via Compose, CI commands | Ansible VM, Argo CD, Loki, full monitoring all stopped |
| **Extended** | 16 GB RAM, ≥60 GB SSD, modern multi-core CPU | One-node kind + app + limited metrics; Ansible guest **run separately** | Full logging/tracing and multi-node cluster |
| **Capstone** | 24–32 GB+ RAM, ≥80 GB free SSD | Multi-node kind, Argo CD, metrics/logs/alerts, VM when capacity allows | Tracing optional |

\* Planning estimates, **not certified minimum specifications**. Actual consumption varies with Windows, Docker/WSL memory caps, node images, cache and data retention. Profile selection is a Phase 00 decision supported by RAM/disk measurements. Do not launch an Ansible VM simultaneously with a full observability cluster on an 8–16 GB machine.

**Preflight checks (run from WSL unless noted):**

```bash
uname -a
cat /etc/os-release
free -h
df -h .
git --version
docker version
docker compose version
wsl.exe --status  # from a WSL environment with Windows interop available; else PowerShell
```

Create `docs/evidence/G00-preflight.md` documenting OS versions, virtualization support, hardware, memory/disk availability, Docker access and the selected execution profile. **Do not copy tokens, usernames, home paths or sensitive environment variables into public logs.**

### Local Linux VM strategy for Ansible

On Windows, use **one** supported local virtualization method after checking compatibility with WSL2/Hyper-V: a VirtualBox Ubuntu guest, Hyper-V on eligible Windows editions, or another reliable local VM backend. Allocate approximately 1–2 vCPU and 1–2 GB RAM to start; install SSH and Python. Keep the guest **isolated and reachable only from the host/control node** using a carefully verified host-only network or restricted NAT port forwarding. Ansible runs inside WSL2, connects to the guest over SSH, and does not treat a Docker container or an additional WSL distro as evidence of a separate guest VM. If hypervisor coexistence fails, execute the VM lab **separately** and record the limitation. Never weaken the Windows firewall globally merely to reach the VM.

### Environment mapping

| Environment | Runtime | Data | Deployment | Exposure |
|---|---|---|---|---|
| `compose-dev` | Local Docker Compose | Ephemeral/persisted volume | `docker compose` | 127.0.0.1 only |
| `dev` | Local kind, namespace `forgeops-dev` | Dedicated PostgreSQL volume | Argo CD auto sync with safe policy | Loopback port-forward |
| `staging` | Same kind cluster, namespace `forgeops-staging` | Separate PostgreSQL volume | PR-reviewed manual promotion | Loopback port-forward |
| `ansible-lab` | Separate Ubuntu VM | Disposable lab state | SSH + Ansible playbooks | Host-only/NAT only |

**Warning:** namespaces within one kind cluster are **logical**, not physical fault-isolated, environments. Use different database credentials and namespaces, but do not claim isolated production-grade staging.

---

## 3. Target architecture and lifecycle

```text
                 DEVELOPER + PUBLIC/PRIVATE SOURCE REPOSITORY
                       | feature branch / reviewed PR
                       v
              GitHub Actions (hosted standard runner)
              ├─ Lint + unit/integration tests
              ├─ Secret / dependency / image scans
              ├─ Build image + SBOM + versioned digest
              └─ Publish to GHCR (trusted main only)
                       |
                       | proposed image-digest change in Git (PR)
                       v
                  GitOps declarations
                       |
                outbound repository pull
                       v
   ┌────────────── Windows / WSL2 / Docker host ─────────────────┐
   │ kind (local Kubernetes; created by checked script)         │
   │    ├─ bootstrap platform: installed once via Terraform     │
   │    │   (selected namespace and Argo CD Helm release)       │
   │    ├─ Argo CD (read-only Git; desired state reconciler)     │
   │    ├─ forgeops-dev: API + PostgreSQL + PVC                  │
   │    ├─ forgeops-staging: API + PostgreSQL + PVC              │
   │    └─ observability: Prometheus, Grafana, Alertmanager,     │
   │           Loki + Alloy (optional Tempo)                    │
   │         ↑ Spring Actuator /metrics / JSON application logs │
   │    [Loopback port-forward for local access]                │
   │                                                            │
   │ Terraform local Docker provider: isolated non-kind lab     │
   │ networks/services; Terraform local state, NOT in Git       │
   └────────────────────────────────────────────────────────────┘
                     separate networking boundary
              Ubuntu VM, SSH-only from WSL2 control node
                    ↑ Ansible roles and playbooks

   OFFLINE MODE: local `make ci` → docker build → kind load image →
                 direct Helm chart validation/deploy in sandbox.
   Restore Argo ownership before re-enabling reconciliation.
```

### Delivery sequence

1. A developer pushes a feature branch and opens a PR; checks run **without publication credentials**.
2. After review, main branch CI runs tests, source/dependency scanning and a non-root Docker build.
3. Only successful trusted main-branch builds publish a tagged image; obtain its immutable `sha256:` **digest**.
4. A workflow or local script **proposes** a Git PR updating only the **dev** image digest in Helm values; PR is reviewed and merged.
5. Argo CD observes desired state in Git over outbound access and reconciles `forgeops-dev`. No inbound tunnel from GitHub is needed.
6. A post-deploy smoke check runs locally when the laptop/cluster is on; CI does not falsely report cluster deployment from a hosted runner.
7. After checks, a separate PR promotes the exact same digest to **staging**, with a manually approved sync policy.
8. On failures, revert the desired-state Git commit or apply a previous known-good digest; with Argo auto-sync enabled, `helm rollback` **alone** is not a durable rollback.

**Control-plane rule:** code/image CI results are hosted; on-device deployment results are generated by a **local verification job**. Neither may be substituted for the other.

### Infrastructure ownership contract (mandatory ADR)

| Resource | Sole owner | Forbidden overlapping owner |
|---|---|---|
| kind cluster containers/nodes | `scripts/cluster/create.sh` using kind | Terraform Docker provider / manual Docker prune |
| local Terraform lab Docker network/container | Terraform `local-docker-lab` root module | Compose / kind / manual Docker writes |
| Ubuntu guest OS, packages, users, service configs | Ansible | Terraform remote-exec / ad hoc `ssh` updates |
| Cluster bootstrap Argo CD release | Terraform Helm provider **only in bootstrap state** | Argo CD self-management before approved handoff |
| App Deployments, ConfigMaps, app Services, Helm chart values | Argo CD rendering Helm | Direct `helm upgrade` / Terraform K8s provider |
| Database contents | PostgreSQL + Flyway for schema changes | Terraform / Helm destructive resets |
| Developer credentials and local secret material | Operator-managed local injection | Git commits or Terraform variables containing secrets |
| Observability releases | Argo CD after bootstrap | Terraform except explicitly documented first bootstrap |

Cilium, if enabled, must be **installed before** enforcing NetworkPolicies, and the cluster creation must be configured to disable kind's default CNI; do not apply this in-place to an existing healthy lab and assume it will work. Use a separate clean kind profile and verify current Cilium/kind compatibility.

---

## 4. Technology selection and version management

| Layer | Decision | Why | Version policy |
|---|---|---|---|
| Java | Supported LTS JDK + Spring Boot matching its release line | Familiar and job-relevant application | Confirm compatibility, pin toolchain & base image digest |
| Database | PostgreSQL + Flyway | Real persistence and migrations | Pin major and image digest |
| Automation | Bash + Python 3 | Operational scripting, health checks | Specify minimum versions in compatibility matrix |
| Container tools | Docker Engine/Compose | Broadly used, local-friendly | Record `docker version` and plugin version |
| Terraform | Terraform CLI + `kreuzwerker/docker` provider | Local IaC exercises without cloud | Pin provider using `.terraform.lock.hcl` |
| Ansible | `ansible-core` + explicit community collections | Reproducible roles, SSH, lint | Lock Python deps and `requirements.yml` |
| K8s | kind + kubectl | Free local cluster | Pin kind node image digest + supported K8s version |
| Helm | Helm chart | Reusable app manifests | Pin chart dependency versions |
| Argo CD | Stable supported release | Pull-based GitOps | Pin chart/release and test upgrade |
| Monitoring | Prometheus + Grafana + Alertmanager | Standard metrics & alerting | Lock Helm chart/OCI image versions |
| Logs | Grafana Alloy + Loki | Supported Grafana logging pipeline | **Do not use EOL Promtail** |
| Tracing | OTel Collector + Tempo (optional) | Trace propagation | Add only after stable metrics/logs |
| Security | Trivy, Gitleaks, optional Syft, policy tests | Scan and explain findings | Pin CLI/tool actions and policies |
| Test/load | JUnit, Testcontainers, k6, Molecule as useful | Build proof and operational test | Pin package/tool versions |
| Extra CI | Jenkins (optional comparison track) | Employer exposure | Isolate Jenkins; never give administrator Docker socket by default |

**Phase 00 outputs:** `docs/compatibility-matrix.md` naming **specific tested versions**, URL of release notes, selection rationale, checksum/digest and update policy. **Do not choose unverified “latest” versions** for real deployment files. Never upgrade all components at once.

---

## 5. Application specification: ForgeTasks API

### Core functional requirements

- Multi-project task management with local accounts; user registration optional, bootstrap test users created only for non-production lab data.
- Project CRUD, Task CRUD; statuses `TODO`, `IN_PROGRESS`, `BLOCKED`, `DONE`; priority `LOW`, `MEDIUM`, `HIGH`.
- Pagination, sorting and filters by project, status, priority, assignee and creation time; safe allowlist for sort columns.
- Validation: nonblank name <=120 characters, title <=200; description <=4000; due date optional; reject invalid status/priority; consistent error model.
- Update optimistic concurrency (version field / HTTP ETag or explicit version); return 409 Conflict on stale modification.
- Basic authentication path using Spring Security and secure password hashing; role separation `USER`/`ADMIN` for lab; use real access checks (a user cannot read another user's private project).
- Database schema migrations via Flyway; initial seed only under dev profile.
- `/actuator/health/liveness` and `/actuator/health/readiness` used by probes; Prometheus endpoint exposed **internally** with authenticated/safely scoped scrape access where possible.

### REST contract (version `v1`)

| Method | Endpoint | Semantics | Expected success |
|---|---|---|---|
| GET | `/api/v1/projects` | List allowed projects | 200 paginated |
| POST | `/api/v1/projects` | Create a project | 201 + `Location` |
| GET | `/api/v1/projects/{id}` | Read one project | 200 / 404 |
| PATCH | `/api/v1/projects/{id}` | Update project | 200 / 409 |
| DELETE | `/api/v1/projects/{id}` | Delete/soft-delete according to documented policy | 204 |
| GET | `/api/v1/projects/{id}/tasks` | Filter/paginate tasks | 200 |
| POST | `/api/v1/projects/{id}/tasks` | Create task | 201 |
| GET | `/api/v1/tasks/{id}` | Read authorized task | 200 / 404 |
| PATCH | `/api/v1/tasks/{id}` | Update task/status/version | 200 / 409 |
| DELETE | `/api/v1/tasks/{id}` | Delete task | 204 |
| GET | `/actuator/health` | Lab health (minimal public detail) | 200/503 |
| GET | `/actuator/prometheus` | Scrape metrics, not public web access | 200 internal |

### Data model

```text
Account(id UUID PK, username UNIQUE, password_hash, role, created_at)
Project(id UUID PK, owner_account_id FK, name, description, version,
        created_at, updated_at, archived_at nullable)
Task(id UUID PK, project_id FK, assignee_account_id FK nullable,
     title, description, status, priority, due_at nullable,
     version, created_at, updated_at)
```

Constraints: all FKs explicit; index `(project_id, status, created_at DESC)` for task browsing; index `(owner_account_id, archived_at)` for owned project query; migrations reversible where safe (roll-forward preferred in normal operations); timestamps UTC in DB; request/trace ID propagated to logs. Tests prove pagination, uniqueness, authorization and concurrency.

### Application nonfunctional acceptance targets (local *learning targets*, not production SLAs)

- Unit/integration tests pass; coverage **≥80% for application business/service code** with documented exclusions; avoid coverage theater.
- Start with a Compose health check within 90 seconds on a warmed machine; actual result recorded.
- On a specified baseline laptop/profile, `k6` **50 virtual users for 2 minutes** with predefined scenario and representative DB contents: HTTP failure rate <1% and p95 request latency <500 ms **if achievable**; measured deviations with cause are acceptable lab findings, not fabricated success.
- Container runs as non-root, supports graceful SIGTERM, sets CPU/memory requests and limits for K8s profile; validates readiness during startup and migrations.
- No secrets in response payloads, logs, container layers, committed source or publicly published test fixtures.

---

## 6. Repository structure and contracts

```text
forgeops/
├── README.md
├── AGENTS.md
├── Makefile
├── .gitignore
├── .editorconfig
├── .gitattributes
├── .github/
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   ├── pull_request_template.md
│   └── workflows/{pr-checks,release,security}.yml
├── apps/forgetasks-api/
│   ├── pom.xml
│   ├── Dockerfile
│   ├── .dockerignore
│   └── src/{main,test}/...
├── infrastructure/
│   ├── terraform/local-docker-lab/{versions,providers,main,variables,outputs}.tf
│   ├── terraform/cluster-bootstrap/{versions,providers,main,variables,outputs}.tf
│   ├── ansible/
│   │   ├── ansible.cfg
│   │   ├── requirements.yml
│   │   ├── inventories/lab/{hosts.yml,group_vars/}
│   │   ├── playbooks/{site,verify}.yml
│   │   └── roles/{baseline,users,ssh-hardening,firewall,docker-host,nginx}/
│   └── vm/{README.md,bootstrap-notes.md}
├── platform/
│   ├── kind/{core,extended,cilium}.yaml
│   ├── bootstrap/{README.md,bootstrap-plan.md}
│   ├── charts/forgetasks/{Chart.yaml,values.yaml,templates/}
│   ├── argocd/{apps,projects}/
│   └── environments/{dev,staging}/
├── observability/
│   ├── prometheus/{rules,targets}/
│   ├── grafana/{dashboards,provisioning}/
│   ├── alloy/{config}/
│   ├── loki/{values}/
│   └── alertmanager/{config}/
├── security/{threat-model,policies,scan-config}/
├── tests/{api,infrastructure,security,load,resilience,smoke}/
├── scripts/{check,cluster,build,verify,backup,restore,cleanup}/
└── docs/
    ├── requirements/{SRS.md,traceability.md}
    ├── architecture/{system.md,network.md,data-flow.md}
    ├── adr/ADR-0001..md
    ├── runbooks/{deploy,rollback,db-restore,incident,cluster-reset}.md
    ├── evidence/{G00-G15}/
    ├── interview/{story-bank.md,architecture-questions.md}
    ├── compatibility-matrix.md
    └── risk-register.md
```

### Branch, naming and review contract

- `main` protected where available: required PR, status checks, reviews when feasible under repository plan. No force-push.
- Conventional Commit format or equivalent; `feat/...`, `fix/...`, `ops/...`, `docs/...` branches; each phase requires its own reviewable PR.
- GitHub workflow jobs must use read-only permissions by default; publish job explicitly requests `packages: write`; do not grant write privileges to untrusted PRs.
- `CODEOWNERS` and review instructions may demonstrate review practices even in a one-person project; never imply another human reviewed what was self-reviewed.
- All evidence includes date, command, environment/profile, expected result, actual result, log/screenshot path, and deviation/ticket if not met.

### Planned Make targets (implement and test, do not presume they exist)

```text
make doctor         # detect prerequisites and profile
make lint           # application + YAML + shell + IaC lint
make unit           # fast unit tests
make integration    # Testcontainers integration tests
make ci             # reproducible local CI subset
make compose-up     # local API + DB
make compose-down
make cluster-create # explicit kind creation with selected profile
make cluster-check
make cluster-delete # requires explicit target confirmation
make tf-plan        # plan only, local lab root
make ansible-check
make deploy-dev     # wrapper for reviewed GitOps/local flow
make smoke-dev
make test-failure   # safe, scoped chaos drill
make backup-db
make verify-backup
make report         # redacted evidence index
```

Destructive targets must require explicit scope and confirmation and refuse unknown Kubernetes contexts; all scripts should use robust Bash strict mode and safe error handling. **Never** wire blind `terraform destroy`, `kind delete cluster`, `docker system prune -a` or database deletion into an implicit default target.

---

## 7. Configuration, secrets, access and data ownership

### Secrets approach (v1)

1. Generate test-only credentials *locally* using approved randomness; keep them in `~/.config/forgeops/secrets/` (mode 0700 directory, 0600 files), never inside the repo.
2. Compose reads `.env.local` (ignored) or an env-file under the private config directory; no default real password in committed Compose YAML.
3. Local Kubernetes bootstrap script creates or updates **pre-existing `Secret` resources**, outside the Argo CD-managed manifest tree. Helm charts reference `existingSecretName` only; the Git repo never contains raw secret data.
4. Backups and restore scripts read credentials only from trusted env/secret sources; commands must avoid printing passwords; verify leaked secrets do not appear in logs.
5. Enforce scoped, non-admin Kubernetes service accounts for workloads; separate human operator kubeconfig from Argo CD/CI credentials.
6. Document secret rotation and cluster recreation: after a cluster reset, re-inject secrets before unpausing application reconciliation.
7. Optional capstone: encrypted declarative secrets using SOPS + age or a properly managed Sealed Secrets key (including recovery-key backups), only after testing bootstrap and restore; no false guarantee that Kubernetes Secrets are encryption-at-rest protected in the default local cluster.

### State and persistence

- Terraform roots have independent **local** backends/state files stored on the operator machine, excluded from Git, restricted by filesystem permissions and backed up securely; document risk of corruption and concurrent operators. Terraform `sensitive` outputs **do not mean state encryption**.
- Compose database uses a named Docker volume; Kubernetes PostgreSQL uses one PVC per namespace in a documented local provisioner. Start with a **single replica** PostgreSQL; no deceptive HA claim.
- kind cluster deletion may destroy or orphan local volumes, so **database backups must be stored on the host outside kind nodes/cluster volumes**, with explicit verification and cleanup controls.
- Retention: metrics 24h core / 3d extended, logs 24h core / 3d extended (example profile defaults, tuned according to disk use). Cloud-style long retention out of scope.
- Logs exclude request authorization headers, passwords, SQL credentials, connection strings with credentials and user personal data.

### Access boundary

- API local binding via `127.0.0.1` and/or `kubectl port-forward --address 127.0.0.1`, not Internet-facing; keep Grafana, Argo CD and Prometheus unexposed by default.
- VM SSH key-only login; prefer disabling password authentication after verified public-key access and preserving console recovery; no global firewall disable.
- CI job does not receive laptop keys, kubeconfig or VM credentials. Local Argo CD uses outbound pull, not GitHub runner → home network access.
- On a public repo, make scanning and PR permissions stricter; do not give forked PR workflows trusted tokens.

---

## 8. Terraform detailed design

### `local-docker-lab` root module

Own exactly: a `forgeops-iac-lab` Docker network and a simple disposable diagnostic service/container (e.g., an internal nginx fixture), plus optional persistent test volume unrelated to kind. **Do not use Terraform to manage the same containers as Compose or kind.** This makes `terraform apply`, `import`, state, drift, change plan and destroy verifiable without fighting Kubernetes.

Deliverables: provider version constraints, committed `.terraform.lock.hcl`, meaningful `variables.tf` validation, outputs, an ADR explaining local backend constraints, `terraform fmt -check`, `terraform validate`, `terraform plan`, `terraform apply` after review, demonstrable drift plan, explicit teardown.

### `cluster-bootstrap` root module

Prerequisite: an existing healthy `kind-forgeops` cluster and known kubeconfig. May own dedicated namespaces needed for bootstrap **and only the initial Argo CD Helm release**. After install, Argo CD owns app charts and observability manifests, **not** the bootstrap-managed Argo CD release itself. Do not attempt to manage Argo CD with itself without a separate migration ADR and acceptance test.

- Use separate state from local Docker lab.
- Kubeconfig provider points at *verified context*; make bootstrap fail fast on wrong cluster context.
- The bootstrap module reads no app/database credentials.
- Keep `terraform destroy` of bootstrap **blocked while GitOps applications exist**; define explicit stop/rescue order, not hidden cascading deletes.
- Cilium installation, if enabled, is an early **cluster bootstrap prerequisite** in a fresh Cilium-compatible kind profile; never let both Terraform and Argo CD claim the same Cilium chart release.

### Terraform success criteria

- Exactly expected resources appear in plan; an attempted unintended deletion is caught in review.
- Repeated `apply` returns no changes in stable conditions.
- A harmless manual drift in the **Terraform-owned lab fixture** is detected and can be reconciled.
- Destroy removes only scoped fixture resources; no kind or Compose resources lost.
- No `terraform.tfstate` or backup state committed, and `.terraform.lock.hcl` is committed.

Reference: https://developer.hashicorp.com/terraform/tutorials/docker-get-started

---

## 9. Ansible detailed design

### Control and managed nodes

- **Control:** WSL2 Ubuntu with `ansible-core`, ansible-lint, SSH client and locked collections.
- **Managed:** separate Ubuntu guest with Python 3, SSH server and a non-root operator user with limited sudo rights where possible.
- **Inventory:** `ansible/inventories/lab/hosts.yml` lists the guest and groups `webservers`, `managed_lab`; DNS/IP stored in untracked inventory override rather than assumed permanent VM IP.

### Required reusable roles

| Role | Tasks | Handlers / tests |
|---|---|---|
| `baseline` | Update package metadata, timezone/UTC policy, essential packages, log rotation | No changes on second run |
| `users` | Deploy ops user and SSH key, correct permissions | SSH key works, unapproved login blocked |
| `ssh-hardening` | Configure SSH safely via Jinja2 template, validate syntax | Handler reload after validation; console fallback |
| `firewall` | Default inbound deny, allow scoped SSH only | SSH stays reachable, closed test port blocked |
| `docker-host` | Install supported Docker Engine/configuration (if guest needs it) | Docker service healthy; guest user permissions justified |
| `nginx` | Install and configure Nginx with a templated site | Curl health endpoint, config check, handler reload |
| `node-exporter` **(extended)** | Expose guest host metrics to **trusted lab network only** | Prometheus target UP when in capstone networking |

### Execution contract

```bash
ansible-inventory -i infrastructure/ansible/inventories/lab/hosts.yml --graph
ansible -i infrastructure/ansible/inventories/lab/hosts.yml all -m ping
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.yml \
  infrastructure/ansible/playbooks/site.yml --check --diff
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.yml \
  infrastructure/ansible/playbooks/site.yml
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.yml \
  infrastructure/ansible/playbooks/site.yml
```

Scope real secrets and redact `--diff` output; don't print files with credentials. Second apply should show `changed=0` **except documented non-idempotent tasks**, which must be fixed or justified. Run `ansible-lint`, syntax check and at least one role-test path (Molecule with an appropriate driver if compatible). Test a deliberate config drift and restoration. Ansible is not a tool for configuring the nodes *inside* kind in this project.

References: https://docs.ansible.com/projects/ansible/latest/getting_started/index.html

---

## 10. Containers and Compose

### Dockerfile acceptance

- Multi-stage build (compilation and runtime separated); pinned parent image by digest after validation.
- Non-root runtime identity; restrictive writable directories; use `.dockerignore` to exclude `.git`, build artifacts, tokens and private files.
- Application configurable with environment variables, health via Actuator and appropriate exit/SIGTERM handling.
- No Docker socket mount inside app, no privileged mode, and no DB password baked in image `ARG`, `ENV`, or layer.
- Image labels include source, revision and version; publish `sha256` digest; produce SBOM and attach/report scan results.

### Compose acceptance

- Services: API + PostgreSQL; health-based dependency sequencing, named storage volume, isolated network and local binding (`127.0.0.1:8080` for API).
- Configuration comes from a redacted sample env template and ignored `.env.local` secrets.
- One command starts the stack after building; one command stops it without deleting the DB volume; explicit separate destructive cleanup.
- Test DB persistence across container recreation, failed connection behavior, healthy migration and offline image build where dependencies are already cached.

---

## 11. CI/CD, versioned image and GitOps promotion

### PR check pipeline (untrusted branch permissions)

1. Checkout pinned tool actions (prefer full SHA pinning), initialize JDK and Maven cache.
2. Lint/format and check YAML, Bash and Terraform/Ansible syntax where tooling exists.
3. Unit tests and Testcontainers-backed integration tests on standard Linux runner (record tests run/skipped).
4. Dependency vulnerability scan and license reporting; secret scanning over relevant committed content.
5. Docker build check; Trivy/SBOM report. Block a release for **unaccepted critical/high vulnerabilities** according to documented policy and track exceptions with expiry; false positives require written evidence.
6. Publish JUnit results, test evidence and redacted reports; expose **no GHCR write token** to fork PR jobs.

### Main release pipeline

- Gates: PR checks green, main-only conditional publication, minimal `packages:write` permission in publish job, immutable `gitSHA` tag + digest output.
- Generate SBOM and retained scan report, avoid `:latest` deployment.
- Create a **PR** to update the **dev** image digest; avoid a hosted workflow applying manifests into local laptop.
- PR review → merge → Argo CD reconcile → locally executed smoke tests; staging has a **separate** promotion PR and approval.
- Ensure pipeline cannot recursively push itself indefinitely, and do not put deployment secrets in workflow outputs.

### Helm and Argo CD contract

- Chart templates: Deployment, Service, ConfigMap, ServiceAccount, optional Ingress only if justified, resource limits, probes, PodDisruptionBudget only where replica count and host constraints make it meaningful, `NetworkPolicy` only under policy-enforcing CNI.
- Values: `values.yaml` stable defaults, `values-dev.yaml`, `values-staging.yaml` with immutable image digest; no plaintext DB credentials.
- Chart checks: `helm lint`, `helm template`, Kubernetes manifest validation, smoke deployment to test namespace; optional `helm test` hook.
- Argo CD `Application` and `AppProject` restrict source repos, namespaces and resource kinds. Dev may enable automated self-heal; **automatic prune remains disabled initially**. Staging synchronization remains manually approved with sync policy clearly documented.
- Rollback mechanism: revert desired state in Git to last-good digest and let controller reconcile. If emergency manual rollback is required, suspend Argo reconciliation first and record timeline; avoid claims that `argocd app rollback`/`helm rollback` remain stable under auto-sync.

### Offline/local path

- `make ci` performs local lint + build + test + security checks with cached tools.
- `docker build` builds local image; `kind load docker-image` loads it; `helm template` validates; a temporary **operator-owned sandbox namespace** can be used for manual `helm install` tests. It is deliberately **not** the Argo CD-owned `dev` namespace.
- GitHub and GHCR are convenient free remote services, not hard dependencies of the *local core application*.

References: https://docs.github.com/en/actions/reference/security/secure-use ; https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/ ; https://kind.sigs.k8s.io/docs/user/quick-start/

---

## 12. Kubernetes and cluster configuration

### Cluster profiles

- `kind/core.yaml`: single-control-plane learning cluster, storage/probes/network exercise; always run on smallest feasible host and measure utilization.
- `kind/extended.yaml`: control-plane + one worker, same host, demonstrating scheduling and node-local limitations.
- `kind/cilium.yaml`: **fresh cluster profile** disabling default kind CNI; Cilium installed and validated before any NetworkPolicy experiment.

### Workloads

- Spring Boot API Deployment: default one replica on Core; two when Extended and CPU/memory allow; Deployment with readiness/liveness/startup probes, safe rolling update policy, requests and limits.
- PostgreSQL: single-instance, dedicated PVC and Service per namespace, explicit database initialization script/migrations; prefer simple stable deployment with clear PVC ownership (StatefulSet appropriate) and no false replication claim.
- Expose API to host with loopback `kubectl port-forward` initially; ingress/gateway is an optional advanced exercise, **not** a reason to expose the laptop publicly.
- All workload identities have dedicated service accounts; set `automountServiceAccountToken:false` unless needed.
- Audit resources, scheduler events, `kubectl describe`, rollout status and logs; run DNS connectivity check between application and DB.

### Storage and persistence caveats

Choose and **document a compatible local storage provisioner**; verify PVC binding, volume location and cluster reset behavior. Stop all stateful workloads, take host backup, test backup integrity before deleting cluster. A new kind cluster cannot be assumed to recover old databases from Docker volumes.

### Networking and security

- Basic kind networking may **not** enforce NetworkPolicy; testing policy requires a compatible policy-enforcing CNI such as Cilium in an explicitly configured clean profile.
- Test allowed API→DB flows, forbidden cross-namespace access and necessary DNS and metrics scrape flows.
- Avoid hard-coding pod IPs, node IPs and Windows/WSL transient addresses.
- Perform resource-profile checks to avoid OOMKilled loops on low-memory machines.

Reference: https://docs.cilium.io/en/stable/installation/kind/

---

## 13. Observability specification — Prometheus, Grafana, Loki, Alloy

### Signal flow

```text
API Actuator/Micrometer + kube-state-metrics + node/container metrics
                         ↓ scrape
                    Prometheus ── alert rules ──→ Alertmanager
                         ↓ PromQL                      ↓
                       Grafana                  local demo receiver
                         ↑
structured JSON logs ─→ Grafana Alloy ─→ Loki ─┘
[Optional] OTel instrumentation → OTel Collector → Tempo → Grafana traces
```

### Instrumentation contract

- Expose Micrometer HTTP server counters/latency histograms with stable route labels **not raw ID-filled URLs**; capture request ID and normalized route; add DB pool metrics, JVM heap/GC and readiness metrics.
- Scrape: application, Prometheus itself, Kubernetes platform (using chart-specific compatible exporters), optional VM exporter only after network verification.
- Logs are JSON with timestamp UTC, level, service, namespace, trace/request ID where available, exception classification, sanitized context. **No tokens, passwords or user personal data.**
- Alloy collects pod logs and forwards to Loki using supported `loki.*` components. **Do not use Promtail** (end of life March 2, 2026).
- Grafana datasources and dashboards defined as code and included in Git; local admin credentials injected privately; do not expose UI on public IP.

### Required dashboards (as code)

| Dashboard | Panels / queries concept | Evidence |
|---|---|---|
| **API golden signals** | requests/s, 5xx fraction, p50/p95/p99 latency (histogram), in-flight requests | Screenshot + load change visible |
| **JVM application** | heap used/max, GC pause, threads, CPU and DB pool | Controlled warm-up and usage |
| **Kubernetes workload** | pod readiness, restarts, CPU/memory usage/requests, deployment replicas | Pod kill + recovery trend |
| **PostgreSQL** | connectivity, pool saturation, DB metrics if compatible exporter installed | DB pause drill |
| **Operations logs** | Loki label selectors for namespace/service and request ID | Logs correlated with failed request |
| **Alert status** | pending/firing/resolved alerts, last change | Alert transition proof |

### PromQL examples (adapt metric/labels after verifying actual scrape data)

```promql
# Application 5xx fraction over 5 minutes. Adjust job name to real target.
sum(rate(http_server_requests_seconds_count{job="forgetasks",status=~"5.."}[5m]))
/
clamp_min(sum(rate(http_server_requests_seconds_count{job="forgetasks"}[5m])), 1e-9)

# p95 request latency (provided Micrometer histogram buckets are configured)
histogram_quantile(0.95,
  sum by (le) (rate(http_server_requests_seconds_bucket{job="forgetasks"}[5m]))
)

# API pod restart increase over 15 minutes (requires kube-state-metrics)
sum(increase(kube_pod_container_status_restarts_total{namespace="forgeops-dev"}[15m]))
```

**Queries are examples, not asserted to work without validation:** Spring/Micrometer export suffixes and dimensional labels vary with versions, customizations and histogram settings. Confirm actual output and explicitly write tests to query Prometheus API with valid samples.

### Alerts and acceptance

| Alert name | Suggested learning trigger | Duration | Response |
|---|---|---|---|
| `ForgeTasksDown` | `up{job="forgetasks"} == 0` | 2m | Check application/pod and target discovery |
| `ForgeTasksHighErrorRate` | 5xx fraction >5%, **guard with minimum request rate** | 5m | Compare new image, check logs and DB |
| `ForgeTasksHighLatency` | p95 >750ms while load is meaningful | 5m | Inspect heap, DB pool and dependency latency |
| `ForgeTasksPodRestarts` | restart count increases repeatedly in window | 5m | `kubectl describe`, previous logs, resource limits |
| `ForgeTasksDBUnavailable` | DB dependency signal fails | 2m | DB connection/volume diagnosis |

Thresholds are **initial lab choices**, not production SLOs. Prometheus recommends alerting mainly on user-facing symptoms rather than pages for every possible cause. Keep VM/host alarms as informational if they have no useful action.

Alerts route to a **local test receiver** or Grafana/Alertmanager UI; do not require SMS/email subscriptions. One drill proves `pending → firing → resolved`, including captured timestamps and the runbook link.

### Optional OpenTelemetry / Tempo

Only after existing dashboards and logs pass gate: instrument a trace ID through API → PostgreSQL query span; export via OTLP to collector → Tempo; view trace from Grafana and correlate with logs. Don't claim cross-service tracing for a one-service app.

References: https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/ ; https://grafana.com/docs/loki/latest/send-data/promtail/ ; https://prometheus.io/docs/practices/alerting/

---

## 14. Security and DevSecOps specification

### Threat model

| Threat | Entry point | Control | Evidence |
|---|---|---|---|
| GitHub PR supply chain | Untrusted workflow input | Minimal workflow permissions, pin external actions, no trusted tokens | Fork-style PR test |
| Hard-coded secrets | Source, `.env`, image layers, log lines | Git ignore, Gitleaks, local injection, scan history | Inject mock token in test branch → scanner fails |
| Vulnerable dependency/image | Maven/OCI layers | Dependency scans + Trivy with severity policy + SBOM | Known test fixture flagged |
| Container privilege escalation | App workload | Non-root, no privilege escalation, drop capabilities, readonly filesystem where workable | Policy validation |
| Lateral Kubernetes traffic | Pods and services | Cilium NetworkPolicy, dedicated namespaces, restricted service accounts | Blocked/allowed network tests |
| Over-broad access | Kube role, CI token, guest sudo | Least privilege, RBAC, account separation | Forbidden API action test |
| DB exposure/data loss | PostgreSQL and volumes | Internal Service, credential hygiene, independent backups | External access blocked + restore proof |
| Exposed dashboards/control plane | Grafana/Argo/Prometheus | Bind to 127.0.0.1 and authentication | Port scan from non-host perspective |
| Unsafe automation | shell/Terraform/Ansible | Scoped targets, dry run, reviewed plan, no global cleanup | Abort destructive command test |

### Release policy

- **Critical** open vulnerabilities block production-like release unless a reviewer documents applicability and safe exception; **High** vulnerabilities require a remediation decision with severity, compensating control, owner and deadline. Do not declare a project secure because a scanner ran.
- Generate SBOM in a standard format (CycloneDX or SPDX), store as release evidence; optionally sign image/attestations in advanced phase using supported mechanism.
- Detect leaked tokens with Gitleaks using *fake canary credentials*, never commit real cloud tokens for testing.
- Use `kubectl auth can-i` and disposable pod tests to prove workload access restrictions, including denial cases.
- Add `shellcheck`, `hadolint`, `ansible-lint`, `terraform fmt`, `tflint` (if compatible), Helm lint and Kubernetes schema validation as separate tooling checks.

---

## 15. Reliability, testing, incident management and recovery

### Reliability goals and method

- Lab **availability objective**: after a single stateless API pod is killed, Kubernetes replaces it; if two replicas are configured and readiness works, service should remain callable during one pod's loss. On single replica, a brief interruption is expected.
- Initial measured **RTO exercise target**: restore service within 60 minutes for a tested, documented **local DB loss + cluster recreation scenario**; **RPO goal**: at most one scheduled backup interval (e.g., 24h). These are **exercise targets**, not guaranteed recovery guarantees; report measured results.
- Database backups captured via `pg_dump` with database version awareness, stored in trusted host directory outside kind data; `pg_restore` into fresh DB instance, test row counts/referential integrity and application behavior. Do **not** assume `pg_dump` includes server-wide roles/privileges unless separately backed up or provisioned.
- Practice deploy rollback through **Git revert of immutable digest**, then prove correct version is serving. For failed Flyway migration, analyze schema forward compatibility and avoid assuming database schema rollback occurs automatically.
- Failures must be injected into designated **lab** resources only. Record baseline, trigger, signals, diagnosis, mitigation, verified outcome and lessons.

### Resilience drill matrix

| ID | Injected event | Detect | Recover | Gate evidence |
|---|---|---|---|---|
| DR-01 | Delete 1 stateless API pod | K8s event and restart | Deployment controller recreates pod | Pod and readiness timeline |
| DR-02 | Deploy nonexistent image digest to dev | ImagePullBackOff/rollout failure | Git revert to known-good digest | Healthy rollout restored |
| DR-03 | Generate 5xx responses for 5m | Prometheus/Alertmanager | Remove deliberate fault | Alert pending/firing/resolved |
| DR-04 | Pause database process | Readiness/log signals | Restart DB, inspect data | SQL and API confirmation |
| DR-05 | Induce CPU/load pressure via k6 | p95/CPU curves | End load; scale/tune if warranted | Grafana chart + report |
| DR-06 | Manually change Argo-owned safe annotation | OutOfSync/self-heal | Controller reconciles | Before/after diff |
| DR-07 | Delete disposable DB data | Application error | Verified backup restore into fresh DB | Row count + checksum/sample validation |
| DR-08 | Block forbidden cross-namespace connection | Network test fails as designed | No recovery; policy is control | Allowed/denied table |
| DR-09 | Break Ansible Nginx config in guest | Nginx check failure | Idempotent role reapply | Service green + no unintended changes |
| DR-10 | Terraform fixture drift | `terraform plan` diff | Approved `apply` | Recorded state/plan comparison |

### Incident response document template

1. Incident ID, UTC start/end and declared severity.
2. Symptoms and users/functions affected; avoid invented customer impact.
3. Telemetry evidence: alert labels, panel screenshots, logs, command output, commit digest.
4. Time-ordered actions with decision points and rollback conditions.
5. Root cause vs contributing factors; differentiate proved facts from hypotheses.
6. Recovery confirmation and exact RTO/RPO measurement.
7. Prevention actions with priority, owner (self), tests, and follow-up PR references.

### Backup safety

`make backup-db` refuses if disk free space is insufficient; creates a timestamped backup with restricted permissions and checksum. `make verify-backup` attempts a **test restore** into a scratch database rather than treating file existence as successful backup. `make restore-db` requires a **non-production context confirmation**, backup integrity check, destination explicit, and pre-restore snapshot. Never restore over the only existing database without a recoverable copy.

---

## 16. Risk register and constraints

| ID | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R01 | Laptop lacks RAM for Argo, Loki, K8s and VM | High / Medium | Run profiles sequentially; add resource/retention caps |
| R02 | WSL2 + local guest hypervisor conflict | Medium / Medium | Preflight; select compatible backend; separate sessions |
| R03 | Public CI triggers unintended publish privileges | Medium / High | Least privilege, protected main, separated jobs |
| R04 | Accidental loss of DB via kind deletion | Medium / High | Host backups, verify restore, scoped cleanup guard |
| R05 | Secret leaks to public GitHub | Medium / High | Local injection, Gitleaks, ignore, redaction |
| R06 | Argo and Terraform resource ownership collision | Medium / High | Explicit ownership contract, namespace/label inventories |
| R07 | NetworkPolicy resources but no enforcement | High / Medium | Cilium-enabled clean cluster and negative tests |
| R08 | Unrealistic SLA/HA claims from kind | Medium / High reputational | Document local-only failure domain and test scope |
| R09 | Stale/incompatible dependencies | Medium / Medium | Compatibility matrix and controlled upgrades |
| R10 | Scope creep from 20+ tools | High / Medium | Gate-controlled phases, optional extras deferred |
| R11 | Local disk explosion from images/logs | High / Medium | Bounded retention, selective cleanup, disk checks |
| R12 | Accidental network exposure of Argo/Grafana | Medium / High | Loopback-only bind, password auth, external port check |
| R13 | GHCR or hosted runners change pricing/limits | Medium / Low | Check current terms, default public standard runner, local build fallback |
| R14 | Database schema out of sync with app rollback | Medium / High | Expand/contract migration design, forward compatibility |

**Risk review required** at gate 00, 05, 08, 10 and 13; record mitigations as implemented only after proof.

---
## 17. Phased implementation program (G00–G15)

**Execution model:** no more than one active implementation gate at a time. Each gate closes only when its dependencies, deliverables, tests, learning notes and independent proof are reviewed. A gate may be marked **Passed**, **Passed with documented limitation**, or **Failed / Blocked**. Never equate source files merely existing with a passed gate.

### G00 — Feasibility, architecture and baseline

**Dependencies:** none. **Target:** hardware/OS feasibility and an architecture ready for implementation.

**Build tasks**

1. Inspect existing folder and Git status; preserve existing work.
2. Capture hardware, WSL, virtualization, Docker Engine, network and disk preflight. Test basic Docker container launch; verify license eligibility.
3. Choose Core/Extended/Capstone profile based on measurements; define stop/start and memory pressure procedure.
4. Write project charter, SRS, system/data/network diagrams, component responsibility/ownership matrix and ADRs 0001–0008.
5. Decide exact verified versions after reviewing current upstream compatibility; record links, platform support and locking strategy.
6. Add repository baseline `.editorconfig`, `.gitignore`, CODEOWNERS, basic Makefile, shell safety checks and license/readme.
7. Define nonfunctional targets and test provenance. Start risk register and phase traceability.

**Deliverables:** `docs/requirements/SRS.md`, architecture docs, compatibility matrix, `docs/adr/*`, `docs/evidence/G00-preflight.md`, project roadmap and repository baseline.

**Acceptance:** Docker works; selected lab profile is justified; repo ignores private files; the core app/CI/infrastructure/data flows are traceable; reviewer confirms no tool ownership overlap. **Do not write application code before G00 review.**

### G01 — ForgeTasks API and database correctness

**Dependencies:** G00.

**Build tasks**

1. Create Spring Boot application with controller/service/repository/domain layers but no unnecessary distributed services.
2. Implement `Account`, `Project`, `Task`, Flyway migrations, constraints, indexes and optimistic lock/version semantics.
3. Add validation and RFC-style structured error responses with consistent request IDs.
4. Configure security and demonstrable owner-level authorization; use a local bootstrap user fixture restricted to test profile.
5. Implement task/project CRUD, filters and pagination; generate OpenAPI docs.
6. Add Actuator liveness/readiness and Micrometer registry wiring; verify metrics endpoint is not exposed to arbitrary external clients.
7. Write JUnit/Mockito unit tests, Spring integration tests and Testcontainers PostgreSQL tests, including migration upgrade and fault cases.

**Acceptance:** repeatable clean-build test suite; actual PostgreSQL integration verified; all listed APIs respond correctly, unauthorized cross-user access is rejected, version conflict returns 409, health probes and schema migrations work. Capture test reports and sample API commands in `docs/evidence/G01/`.

### G02 — Docker/Compose and runtime hardening

**Dependencies:** G01.

**Build tasks:** multi-stage Dockerfile, non-root runtime, minimal image, `.dockerignore`, local secrets injection, health endpoints, graceful shutdown, Compose API+DB+volume+network, loopback bind, smoke script and data persistence test.

**Acceptance:** fresh Docker Compose startup passes; API can create/read records; `docker compose down` and up retains records; removing an app container does not delete DB data; container user is non-root; no secrets in image layers. Record image size and runtime memory as baselines.

### G03 — CI, trust boundaries and GHCR image publishing

**Dependencies:** G02.

**Build tasks:** PR workflow with lint, tests, Testcontainers where compatible, Gitleaks, dependency scan, Docker build, Trivy; main-only trusted release job publishing versioned image to GHCR; artifacts include SBOM, reports and image digest. Pin workflow actions to verified immutable commits where feasible; use least-privilege job permissions. Implement local `make ci` counterpart.

**Acceptance:** failing test causes red workflow; secret canary in an isolated test branch is detected before merge; non-main/fork PR cannot publish; accepted main change produces immutable digest and corresponding report; local CI is documented. Screenshot/GitHub job links retained with sensitive values redacted.

### G04 — Linux guest and Ansible roles

**Dependencies:** G00; G02 preferable for guest service demo.

**Build tasks:** establish genuine Ubuntu VM; verified SSH from WSL2 control node; inventory, package pinning, reusable roles `baseline`, `users`, `ssh-hardening`, `firewall`, `nginx`, optional `docker-host`; Jinja2 template, Vault test data, handlers, `ansible-lint`, check-mode and safe drift test.

**Acceptance:** accessible guest with correct SSH policies and intended packages; Nginx serves lab content; after first converge a second playbook run reports no unplanned changes; a manual safe change is corrected by Ansible; firewall blocks designated test port without blocking SSH; saved role evidence. Do not count a container as the guest VM.

### G05 — Local Terraform provisioned infrastructure

**Dependencies:** G00 and functioning Docker; separate from G04.

**Build tasks:** `local-docker-lab` Terraform root, provider lock and optional module, network+fixture lifecycle, validation/plan/apply workflows, local state backup, drift demo and scoped destroy. Produce ADR for separation from Compose/kind.

**Acceptance:** `fmt -check` and `validate` pass; initial plan reviewed; apply creates only expected fixture; repeat apply no changes; plan detects altered fixture; safe destroy removes only fixture and preserves Compose/kind.

### G06 — Kubernetes core in kind

**Dependencies:** G02, G05 familiarity; no hard Terraform cluster dependency.

**Build tasks:** validate kind and kubectl; create single-control-plane cluster via explicit script; local storage provisioner and documented PVC semantics; write initial vanilla manifests for API+Postgres; service DNS, probes, requests/limits, namespace separation, graceful rollouts. Load local image through `kind load docker-image` for offline sandbox.

**Acceptance:** both isolated namespaces can run unique database instances; API health and SQL pass; pod deletion triggers replacement; PVC binding and DB persistence after pod restart verified; host access restricted to loopback; status report includes real available memory and OOM behavior.

### G07 — Helm reusable application chart

**Dependencies:** G06.

**Build tasks:** chart helpers/labels/selectors, Deployment/Service/ConfigMap/ServiceAccount/PVC-related definitions as appropriate, `existingSecretName` binding, `values-dev`/`values-staging`, resource/probes configuration, `helm lint`, chart tests, schema validation and template snapshots. Do **not** install persistent app releases simultaneously through both manual Helm and Argo.

**Acceptance:** chart renders valid, distinct dev/staging manifests; overrides result in correct names and resources; no plaintext secret appears in rendered output; isolated temporary install works and uninstalls safely. Record chart release/version and compatibility requirements.

### G08 — Platform bootstrap and Argo CD GitOps

**Dependencies:** G06–G07, G05 Terraform familiarity.

**Build tasks:** `cluster-bootstrap` Terraform root takes verified kind kubeconfig, installs initial Argo CD Helm release; define restricted Argo `AppProject`, `Application` for dev and staging; map exact ownership boundaries; configure outbound Git repository and GHCR pull; manifest digest update PR; conservative sync and drift controls; documented Git revert workflow.

**Acceptance:** PR-based dev digest change is detected and synchronized; `dev` reports correct digest; staging remains unchanged until promoted; safe manual drift is detected and reconciled in dev; failed image deployment is recovered through a **Git desired-state revert**, not a non-durable blind Helm rollback. Terraform `plan` reports only its bootstrap resources.

### G09 — Prometheus, Grafana and Alertmanager

**Dependencies:** G06, app metrics from G01, GitOps from G08 ideally.

**Build tasks:** add pinned metrics Helm chart to GitOps; record scrape endpoints and generated labels; provision Prometheus rules, Grafana datasource and versioned dashboards; configure Alertmanager local receiver; instrument API HTTP latencies, errors, JVM resources, readiness and selected DB metrics.

**Acceptance:** scrape targets UP; a real API call changes request rate graph; k6 impacts p95 and CPU; metrics show valid units and bounded label cardinality; a deliberate 5xx failure transitions alert `pending→firing→resolved` and response runbook link works; metric retention and memory under profile budget. Do not mark passed from a blank default Grafana homepage.

### G10 — Loki and Grafana Alloy centralized logging

**Dependencies:** G09 and G06.

**Build tasks:** deploy Loki in local single-binary/lab suitable mode; collect pod logs using Grafana Alloy (not Promtail), normalize bounded labels, redact sensitive fields, configure Grafana Loki datasource and query dashboards. Introduce request ID/trace ID log correlation.

**Acceptance:** an intentionally failing API request generates redacted structured log retrievable from Grafana by timestamp+service+request ID; pod replacement does not erase retained logs within retention window; no auth header/password appears in sample logs; storage and ingestion caps documented.

### G11 — Security, RBAC and supply chain

**Dependencies:** G03, G06–G10.

**Build tasks:** threat model, scanner threshold policy, SBOM, reduced container privileges/capabilities, read-only root FS if feasible, resource controls, dedicated service accounts, RBAC negative tests, secure local secret generation/rotation. Add separate clean Cilium-enabled kind profile and enforce NetworkPolicies only after CNI verified; run positive and negative network flows.

**Acceptance:** deliberate mock secret detected; critical test fixture vulnerability or explicit policy violation blocks CI; forbidden namespace API access denied; forbidden pod networking blocked under active Cilium; allowed API→DB and DNS remain functional; no operator/admin permission embedded in pods; registry image scans produce tracked outcomes.

### G12 — Reliability engineering and measurable load

**Dependencies:** G08–G11.

**Build tasks:** k6 representative scenarios and reproducible data fixture; collect baseline HTTP latency/throughput, DB behavior, memory and CPU; test rolling updates, readiness failures, pod kill, deliberately invalid image and Argo Git revert. Define lab SLI/SLO and error-budget *exercise* (not public SLA); write first incident runbook.

**Acceptance:** each drill has setup/expected/actual/recovery evidence; metrics logs correlate with failure timeline; known-good digest restored and application health rechecked; performance limits and hardware profile stated; no tests harm non-lab resources.

### G13 — Database backup, disaster recovery and cluster reset

**Dependencies:** G06–G12; standalone backup automation may be developed earlier.

**Build tasks:** verified host-side `pg_dump` with naming/manifest/checksum/permissions, restoration into new DB, row count/sample checks, versioned restore runbook, PostgreSQL credentials and role provisioning strategy; simulate local kind loss after confirming backup. Create explicit cluster bootstrap order covering CNI, Argo, secret reinjection, PVCs, app and observability.

**Acceptance:** from a documented clean environment and backed-up test dataset, restore into scratch DB and demonstrate task/project records available via API. Record measured restore duration, data age and which components were recovered. If recovery target missed, record **Failed with evidence** and fix rather than invent success. Clean up temporary restores only after verifying permanent backup remains intact.

### G14 — Advanced platform comparison (optional, but planned)

**Dependencies:** stable G12–G13 core; sufficient hardware.

Choose subtracks one at a time; each has separate acceptance proof:

- **Jenkins**: local isolated Jenkins container, pipeline-as-code invoking identical test/build quality gates to Actions, protected credentials and no privileged host Docker socket by default; compare trade-offs in ADR.
- **OpenTelemetry + Tempo**: trace exporter/collector/Tempo, contextual request ID log link and one API-to-DB span trace; verify actual end-to-end trace.
- **Ingress / HTTPS**: local-only TLS termination with Nginx/Traefik and test CA, TLS renewal design; never claim publicly trusted cert without domain control.
- **Ansible Molecule**: role convergence, idempotence and verification suite run in disposable suitable environment.
- **Enhanced secrets**: SOPS+age with bootstrap key management and tested key recovery; or appropriate Sealed Secrets path if consciously chosen.
- **Policy-as-code**: Kyverno / OPA Gatekeeper tests on pod privilege and registry rules, only if host capacity allows.

Every extra tool requires an explicit problem statement, resource estimate, owner, failing/working scenario and teardown path. It is legitimate to leave this gate deferred.

### G15 — Final audit, evidence and portfolio handoff

**Dependencies:** G00–G13 passed or transparent limitation recorded; G14 optional.

**Build tasks:** full reproducibility audit; review threats/risk register; trace SRS requirements to files/tests; backup evidence; publish architecture/data/network diagrams; public project README; operational runbooks; architecture decision summaries; 3–5 minute demo video (optional actual recording); screenshots of pipelines, dashboards, alerts and failed/recovered scenario; realistic CV bullet points and interview Q&A.

**Acceptance:** a reviewer can follow clean setup and run Compose core from docs; advanced profile start succeeds on qualified hardware with documented limitations; three representative failure tests reproducible; all critical vulnerability exceptions tracked and no real secrets published; project status table says exactly which features were **implemented, tested, partial, not implemented**. CI results and live system screenshots are not simulated.

---

## 18. Dependency chain and schedule

```text
G00
 ├── G01 → G02 → G03
 ├── G04 (can run independently, best after G02)
 └── G05
G02 + G05 → G06 → G07 → G08
G01 + G08 → G09 → G10
G03 + G08 + G10 → G11 → G12 → G13
G12 + G13 → G14 optional
G00–G13 → G15
```

**Suggested pacing (not a promise):** 16–24 weeks at roughly 10–15 hours/week, slower on 8 GB machines or during deep troubleshooting. One gate may consume multiple weeks, particularly Kubernetes/GitOps, reliable VM networking, and observability. You can apply to junior jobs after G03–G06 with a truthful CV; do not wait for every optional phase.

| Weeks (illustrative) | Gates | Interview-ready story |
|---|---|---|
| 1–2 | G00–G01 | Build and test a useful API with schema migration |
| 3–4 | G02–G03 | Secure container and pipeline; CI failure demonstrated |
| 5–7 | G04–G05 | SSH-managed Linux, Ansible automation, Terraform lifecycle |
| 8–11 | G06–G08 | Kubernetes, Helm, GitOps rollout and Git revert |
| 12–15 | G09–G10 | Prometheus/Grafana dashboards and Loki log correlation |
| 16–19 | G11–G12 | Least-privilege platform and controlled incidents |
| 20–22 | G13 | Measured DB backup/restore exercise |
| 23–24 | G15 (G14 only if feasible) | Reproducible public portfolio and architecture narrative |

---

## 19. Acceptance test matrix and evidence schema

Each test case has `ID`, `Gate`, `Prerequisites`, `Command/Action`, `Expected`, `Observed`, `Result`, `Evidence`, `Reviewer`, `Date`, `Hardware profile`. Write these into `docs/evidence/Gxx/acceptance.md` and run them on the version recorded in the compatibility matrix.

| Test ID | Gate | Requirement | Minimum proof |
|---|---|---|---|
| A-001 | G00 | Prerequisites | `doctor` report and Docker runtime version |
| A-101 | G01 | API correctness | Passing unit/integration test result |
| A-102 | G01 | Authorization | Denied cross-owner project read |
| A-103 | G01 | Migration | Clean DB migrates; re-run consistent |
| A-201 | G02 | Non-root container | Container UID/privilege proof |
| A-202 | G02 | Persistence | Data preserved across API recreation |
| A-301 | G03 | PR trust boundary | Fork/untrusted branch cannot publish |
| A-302 | G03 | Published image | GHCR digest + SBOM + scan |
| A-401 | G04 | Ansible converge | SSH guest status + role results |
| A-402 | G04 | Ansible idempotence | Second run changed=0 except documented |
| A-501 | G05 | Terraform lifecycle | Approved plan/apply and drift plan |
| A-502 | G05 | Safe destroy | Kind and Compose untouched |
| A-601 | G06 | Kubernetes workload | Healthy pods, endpoints, bound PVC |
| A-602 | G06 | Recovery | Deleted stateless pod replaced |
| A-701 | G07 | Chart and profiles | Dev/staging manifest diffs and lint |
| A-801 | G08 | GitOps sync | Approved desired-state digest deployed |
| A-802 | G08 | Failed release recovery | Git revert → healthy digest |
| A-901 | G09 | Metrics | Prometheus target UP; graph reacts to k6 |
| A-902 | G09 | Alerts | pending/firing/resolved captured |
| A-1001 | G10 | Logs | Request ID and failure found in Loki |
| A-1101 | G11 | Secret scanning | Canary secret blocked by pipeline |
| A-1102 | G11 | Network enforcement | Denied bad flow, allowed good flow |
| A-1103 | G11 | RBAC | Forbidden `kubectl auth can-i` result |
| A-1201 | G12 | Load experiment | k6 result correlated with dashboard |
| A-1202 | G12 | Incident response | Complete timeline/runbook |
| A-1301 | G13 | Backup integrity | SHA/size and successful scratch restore |
| A-1302 | G13 | Cluster rebuild | Recorded time and data integrity |
| A-1501 | G15 | Reproducibility | Fresh setup walkthrough and honest status |

**Pass definition:** expected behavior happened; actual command/result is in evidence; no hidden manual fix omitted. If an environment is unavailable, mark *Blocked*—not Passed.

---

## 20. Operating runbooks to author

### `runbooks/deploy.md`

1. Confirm expected `git` revision and correct kube context (`kind-forgeops`).
2. Confirm kube nodes, Argo and DB healthy.
3. Review image digest and migration compatibility, update desired-state branch and PR.
4. Merge approved Git state change; watch Argo sync/health, rollout and logs.
5. Run `smoke` and verify Prometheus metrics, API version, task read/write.
6. Record artifact digest, commit, timing, status and evidence.

### `runbooks/rollback.md`

1. Declare incident and scope (app-only vs DB schema issue).
2. Stop further promotions; identify last-known-good digest and Git commit.
3. Revert Git desired-state commit; do not do unmanaged Helm rollback under enabled auto-sync.
4. Confirm Argo sync and healthy workloads, API success and data migration compatibility.
5. Record telemetry and follow-up fix.

### `runbooks/db-restore.md`

1. Confirm disposable/local environment and stop writes.
2. Validate backup manifest/checksum and restore tool compatibility.
3. Restore to a **new scratch DB** first; verify migrations, counts and business query.
4. Plan destination cutover with backup of present DB; update secret references as needed.
5. Switch app, smoke test, record RTO/RPO and preserve pre-cutover backup.

### `runbooks/incident.md`

Start with impact and safety; `kubectl get pods,deploy -A`, `kubectl describe`, previous logs, Prometheus targets and dashboard/Alertmanager, release Git diff and DB status; record hypothesis, mitigation and recovery. Avoid killing random pods to “fix” symptoms without checking cause.

### `runbooks/cluster-reset.md`

Explicit context check; export evidence and backups; stop GitOps applications; uninstall owned resources by prescribed owner only; remove kind via scoped command; recreate cluster profile; provision Cilium first if selected; Terraform bootstrap Argo; restore out-of-band local secrets; reconcile apps; restore DB; smoke test and monitoring. Never delete unrelated Docker volumes.

---

## 21. Antigravity IDE agent rules and review-driven workflow

The recommended `AGENTS.md` is supplied alongside this plan. At the beginning of each coding session, the agent must:

1. Read `AGENTS.md`, this master document and relevant ADRs; show `git status` (do not overwrite existing code).
2. State gate, expected deliverables, file changes, risks and commands; propose implementation plan for approval.
3. Use **official upstream documentation** for specific installed versions; do not assume config syntax from outdated tutorials.
4. Implement the **smallest reviewable vertical slice**; do not install all tools, enable external networking or create a cloud account autonomously.
5. Run lint, tests and acceptance checks. Record exact command, exit code, observed result and blockers.
6. Create the verification walkthrough and update SRS traceability, risk/ADR/compatibility docs when choices change.
7. End with a gate decision **Passed / Passed with documented limitation / Failed / Blocked**, then wait for user selection before implementing the next gate.

### Agent prompts by checkpoint

**First prompt:**

> Read AGENTS.md and FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md. Inspect the current workspace without overwriting any files. Execute only non-destructive preflight checks, produce a G00 feasibility report and a reviewable implementation plan with exact verified tool versions and ADRs. Do not begin G01 or provision infrastructure without reviewing the G00 outcome.

**Implementation prompt after a gate is chosen:**

> Implement only gate Gxx from the ForgeOps plan. Before changing code, list files and tests you intend to change, architectural boundaries, and any destructive or credential-bearing operations. Use the selected hardware profile. Run all acceptance tests you can. State precisely which tests actually ran, with evidence, failures and next steps. Do not claim later gates are implemented.

**Security review prompt:**

> Review the current ForgeOps phase as a DevSecOps reviewer: identify secret leaks, network exposure, CI trust boundary, RBAC overprivilege, Terraform/Argo/Ansible ownership collisions, data-loss paths and recovery gaps. Propose minimal fixes and tests. Do not execute destructive actions.

---

## 22. Architecture decision records to create first

- **ADR-0001 — Local-first architecture:** paid cloud services not needed; limitations of single host.
- **ADR-0002 — One application, not distributed microservices:** operational complexity remains demonstrable without pointless splits.
- **ADR-0003 — Resource ownership and lifecycle:** kind scripts vs Terraform bootstrap vs Ansible vs Argo/Helm.
- **ADR-0004 — Pull-based GitOps:** hosted CI cannot directly connect to local laptop; promotion by Git PR and digest.
- **ADR-0005 — State and data management:** independent Terraform roots, Postgres PVC backups outside cluster.
- **ADR-0006 — Secrets:** local out-of-band secret injection; no raw secrets committed; future SOPS option.
- **ADR-0007 — Observability:** Prometheus metrics, Grafana dashboards, Alloy→Loki logs; tracing optional.
- **ADR-0008 — Hardware execution profiles:** core vs extended vs capstone, optional tooling.
- **ADR-0009 — Container image trust and GHCR:** publish permissions, reproducible digest-based deploy.
- **ADR-0010 — Rollback/migrations:** Git revert, readiness, forward-compatible schema approach.
- **ADR-0011 — NetworkPolicy:** Cilium clean cluster profile required for enforcement proof.
- **ADR-0012 — Lab SLO and failure scope:** metrics meaningful in constrained local environment.

Every ADR should contain *Context / Options / Decision / Consequences / Trade-offs / Tests / Reconsideration triggers*.

---

## 23. Final documentation, CV and interview deliverables

### Public README structure

1. What problem ForgeOps solves, architecture diagram, concrete boundaries and local-only limitations.
2. Tool stack and what each tool owns (Ansible **and** Terraform explicit).
3. Core one-command Docker Compose setup and troubleshooting.
4. Advanced kind/Argo/Grafana requirements with realistic hardware advice.
5. CI badges, exact test/evidence references, public scan results (redacted).
6. Grafana dashboards: screenshots **from actual running metrics**, not stock images.
7. Incident drills: bad image recovery, alert firing, backup restore.
8. Known risks, missing features, costs/terms and compatibility matrix.
9. Evidence index and reproducibility instructions; optional demo clip.

### Credible CV bullets **only after the referenced work has passed**

- Designed a local Kubernetes delivery platform for a Java/PostgreSQL service using Helm, pull-based Argo CD GitOps and immutable container image digests.
- Automated Linux host configuration using SSH-based Ansible roles and verified idempotence; managed independent local infrastructure through Terraform with drift and lifecycle tests.
- Implemented GitHub Actions CI, dependency/secret/container scans, SBOM generation and protected image publication to GHCR.
- Built Prometheus/Grafana monitoring, Loki/Alloy centralized logs and actionable alerts; demonstrated incident detection, Git-based rollback and tested PostgreSQL restoration.

These bullets are **future claims only**; do not put them on a CV until evidence exists.

### Architecture interview topics

- Why did Terraform not own the kind nodes? How would ownership change on cloud infrastructure?
- Why should a GitHub runner not directly deploy into your local machine?
- How do GitOps, Helm and Terraform differ, and how do you prevent control-plane conflict?
- If Grafana shows rising p95 and DB pool saturation, how do you triage and prove root cause?
- What happens to data if kind is deleted, and exactly what did your restore test prove?
- How did you verify Cilium actually enforced your NetworkPolicy?
- How do you roll back an image if Flyway changed the database schema?
- What did you deliberately **not** build, and why?
- How would you adapt this system for AWS, on-call SRE, multi-zone high availability and real secret management?

---

## 24. Completion rubric and definition of done

Score the finished project against **evidence**, not number of logos used.

| Category | Weight | Excellent outcome |
|---|---:|---|
| Architecture and ownership | 15 | Clean boundaries, justified ADRs, correct dependencies |
| CI/containers and app | 15 | Tests, supply-chain evidence, stable deployment |
| Ansible and Terraform | 15 | Real VM idempotence; scoped IaC, drift, state safety |
| Kubernetes, Helm and Argo CD | 15 | Reproducible local cluster and Git-based promotion/recovery |
| Prometheus/Grafana and Loki/Alloy | 15 | Real live dashboards, effective alerts and correlated logs |
| Security | 10 | Least privilege, blocked negative tests, no leaks |
| Reliability and recovery | 10 | Measured rollback, backup restore and incident drills |
| Documentation/interview evidence | 5 | Reproducible setup, transparent status and trade-offs |
| **Total** | **100** | **A score is justified only for gates demonstrably passed** |

**Core portfolio-ready:** G00–G10 passed, no severe unresolved security exposure.  
**Advanced DevOps-ready evidence:** G00–G13 passed with explicit lab limitations.  
**Capstone:** optional G14 subtracks verified and final G15 peer-style audit completed.

### Final release checklist

- [ ] A clean developer can reproduce Compose core from documented setup.
- [ ] CI and local test suite actually run and have stored evidence.
- [ ] Ansible configures a separate Linux guest and is idempotent on rerun.
- [ ] Terraform controls independent local infrastructure without deleting kind/Compose.
- [ ] Kubernetes app, PostgreSQL, PVCs and probes behave as documented.
- [ ] Helm chart deploys dev/staging; Argo CD sync and Git revert proven.
- [ ] Prometheus targets, Grafana dashboard panels and Alertmanager alert transitions verified.
- [ ] Loki query retrieves a redacted error event collected by Grafana Alloy.
- [ ] Gitleaks and Trivy policies and relevant RBAC/networking denial tests pass.
- [ ] k6 load, bad-image rollback and scratch database restore evidenced.
- [ ] Sensitive files, Terraform state, keys, backups and raw tokens are absent from Git.
- [ ] Every unbuilt feature is clearly listed as planned/deferred rather than implemented.
- [ ] README includes known single-machine availability and storage limitations.

---

## 25. Official sources and verification notes

The following upstream material informed decisions as of **19 October 2026**. For actual coding, review **release-specific** docs and compatibilities; pages change and examples may target later software versions. Documentation links are references, **not evidence the project was executed**.

- Docker Desktop license and free-use conditions: https://docs.docker.com/subscription-billing/desktop-license/
- GitHub Actions public repository standard runner eligibility and billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- GitHub-hosted runners: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
- GitHub Actions secure-use reference: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub Container Registry billing and free public packages: https://docs.github.com/en/billing/concepts/product-billing/github-packages
- Terraform Docker tutorial / provider example: https://developer.hashicorp.com/terraform/tutorials/docker-get-started
- Terraform state: https://developer.hashicorp.com/terraform/tutorials/state
- Ansible getting started: https://docs.ansible.com/projects/ansible/latest/getting_started/index.html
- Ansible idempotence guide: https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_intro.html
- kind quick start, networking and image loading: https://kind.sigs.k8s.io/docs/user/quick-start/
- Cilium on kind: https://docs.cilium.io/en/stable/installation/kind/
- Kubernetes NetworkPolicies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Argo CD automated sync, prune and self-heal: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/
- Grafana Alloy Kubernetes logs: https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/
- Promtail EOL as of March 2, 2026: https://grafana.com/docs/loki/latest/send-data/promtail/
- Prometheus alerting practices: https://prometheus.io/docs/practices/alerting/
- Helm documentation: https://helm.sh/docs/
- Kubernetes core docs: https://kubernetes.io/docs/home/

### Cost caveat

The **software stack and learning path require no paid cloud account**. Standard GitHub-hosted Actions runners are free for qualifying public repositories under the documented rules, but larger runners and some other offerings can be paid, and published GitHub rules can change. GitHub currently documents container image storage and bandwidth for its Container registry as free, and public packages as free; confirm ongoing account/package terms and visibility before long-term automated storage. Docker Desktop is free for specified personal, educational and small-business uses, not unrestricted commercial usage. Local hardware, internet, power and disk are not literally free. Keep the local build, kind image-loading and Docker Compose path available in case a hosted feature or account changes.

---

## 26. Immediate next action: G00 review, not mass installation

1. Create or open the `forgeops/` directory in Antigravity IDE.
2. Place **this file** at `docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md` and accompanying `AGENTS.md` at repo root.
3. Ask the IDE agent to read both, inspect the system, conduct safe preflight and produce G00 architecture documents and **exact version compatibility choices**.
4. Review the plan and approved hardware profile, especially VM networking, WSL2 memory, GitHub permissions and state/data deletion hazards.
5. Implement only G00, capture evidence, then move to G01 in a separate reviewable change.

**End of plan.**
