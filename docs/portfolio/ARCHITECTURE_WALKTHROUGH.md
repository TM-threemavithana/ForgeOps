# ForgeOps: Architecture Walkthrough & Technical Decisions

## 1. Architectural Vision & Design Principles

ForgeOps is architected around five foundational platform engineering tenets:
1. **Zero Paid Cloud Dependencies:** All capabilities must run deterministically on local infrastructure without external cloud vendor locks or cost commitments.
2. **Strict Single-Owner-per-Resource:** Operational domains are strictly decoupled. No tool may mutate or claim ownership of resources outside its defined lifecycle boundary.
3. **Declarative State with Push-to-Pull Inversion:** Infrastructure and application state are defined in Git. GitOps reconcilers (Argo CD) pull changes into the runtime rather than CI pushing changes imperatively.
4. **Three-Pillar Correlated Observability:** Metrics, logs, and distributed traces must share common contextual metadata (e.g., `trace_id`, `request_id`, `service.name`) to enable instant root-cause analysis.
5. **Fail-Closed, Defense-in-Depth Security:** Policies, container constraints, secret management, and artifact verification must reject unauthorized or tampered states by default.

---

## 2. Component Responsibility & Separation of Concerns

To avoid operational collisions, the platform defines rigid boundaries across lifecycle tools:

```
+-----------------------------------------------------------------------------------------+
|                               TOOL LIFECYCLE BOUNDARIES                                 |
+-------------------+-------------------------------------+-------------------------------+
| Tool              | Exclusive Ownership                 | Forbidden Actions             |
+-------------------+-------------------------------------+-------------------------------+
| Kind Lifecycle    | Local cluster creation, nodes, CNI  | Modifying app workloads or DB |
| Terraform         | Local container fixtures, Argo base | Managing cluster lifecycle    |
| Ansible           | Linux OS configuration, SSH control | Managing Kubernetes objects   |
| Helm              | Manifest templating and packaging   | Direct cluster deployment     |
| Argo CD           | Application deployments & sync      | Infrastructure provisioning   |
| Kyverno (CLI)     | Static manifest policy enforcement  | Dynamic mutating webhooks     |
| SOPS + age        | Encrypted secret envelope security  | Managing runtime Pod env      |
+-------------------+-------------------------------------+-------------------------------+
```

---

## 3. Key Architecture Decision Records (ADRs)

The technical evolution of ForgeOps is governed by formal ADRs located under `docs/adr/`. Below are the pivotal architectural decisions:

### ADR-0001: Local Kind Kubernetes Cluster Over Minikube / K3s
- **Decision:** Selected `kind` (Kubernetes in Docker) as the primary local cluster engine.
- **Rationale:** Kind runs multi-node control planes and workers inside standard Docker containers. This enables fast teardown, pinned node images (`v1.29.2`), and reproducible network bridges without Hyper-V or VirtualBox overhead.
- **Trade-off:** Kind's default `kindnet` CNI implements basic host-local IPAM and iptables routing but lacks native eBPF or NetworkPolicy enforcement. NetworkPolicy resources are verified statically rather than actively dropped at the kernel layer.

### ADR-0003: Helm for Packaging, Argo CD for GitOps Synchronization
- **Decision:** Separated templating (Helm) from continuous delivery (Argo CD).
- **Rationale:** Direct `helm install` inside CI pipelines creates hidden cluster state and imperative failure modes. By checking rendered Helm templates into Git or using Argo CD's native Helm repo integration, Git remains the absolute single source of truth.
- **Operational Reality:** Auto-synchronization was disabled in production rehearsal (`G08`) to prevent destructive loops and enforce operator review before reconciliation.

### ADR-0005: Three-Pillar Correlated Observability (Prometheus, Loki, Tempo)
- **Decision:** Integrated Prometheus (metrics), Loki via Grafana Alloy (logs), and Grafana Tempo via OpenTelemetry (distributed tracing) unified by Grafana dashboards.
- **Rationale:** Traditional setups inspect logs, metrics, and traces across disparate tools. By injecting W3C standard `traceparent` headers in Spring Boot and configuring Grafana with derived fields, an engineer can click a high-latency trace span in Tempo and jump directly to the exact Loki log lines emitted during that execution.

### ADR-0008: Disposable Target Isolation for PostgreSQL Disaster Recovery
- **Decision:** Database restore drills must target an ephemeral, freshly initialized database in a separate namespace (`forgeops-dr-lab`) rather than mutating or cleaning the active application database.
- **Rationale:** Restoring over active production tables (`--clean --if-exists`) carries severe blast-radius risk. Target isolation ensures that restore validation can run against genuine schemas while production traffic and PVCs remain untouched.

### ADR-0010: Client-Side Policy-as-Code via Kyverno CLI
- **Decision:** Enforce Kyverno policies client-side inside GitHub Actions CI using `kyverno apply` instead of deploying an in-cluster dynamic admission controller.
- **Rationale:** An admission webhook controller inside a resource-constrained single-node Kind cluster introduces control-plane memory bloat, latency, and deadlock risk if the webhook pod fails. Running Kyverno in CI shifts security left and blocks non-compliant manifests before Git merge.

### ADR-0011: SOPS + age Asymmetric Encryption with Dual Escrow
- **Decision:** Use Mozilla SOPS with `age` public-key cryptography to encrypt Kubernetes secrets in Git, using dual recipients (`Primary Operator` + `Recovery Escrow`).
- **Rationale:** Avoids expensive KMS cloud services (AWS KMS, GCP KMS, Vault). Committing `.enc.yaml` files with `encrypted_regex: '^(data|stringData)$'` protects secrets while leaving Kubernetes metadata, names, and labels unencrypted for linters and Git diffs.

---

## 4. End-to-End Request & Data Flow Walkthrough

```
[User / k6 Load]
       |
       v (HTTP /api/v1/tasks)
[Ingress / Port-Forward :8080]
       |
       v
[ForgeTasks API Pod (Spring Boot 4.1.2)]
   |-- (1) OpenTelemetry Java Agent injects trace_id, span_id
   |-- (2) Controller logs structured JSON with trace_id
   |-- (3) Micrometer records HTTP request duration & status
   |-- (4) Flyway confirms schema; JPA executes SQL via HikariCP
       |
       v (TCP :5432)
[PostgreSQL Pod (StatefulSet + PVC)]
       |
       v (Local HostPath Volume: /var/lib/postgresql/data)
```

1. **Ingress & Tracing:** Traffic hits the ForgeTasks API. The OpenTelemetry Java instrumentation agent intercepts the request, generates a W3C trace context, and attaches `trace_id` to the logging MDC.
2. **Log & Trace Export:**
   - The application writes structured JSON logs to stdout. Grafana Alloy scrapes container logs, extracts Kubernetes labels, strips sensitive data, and streams them to Grafana Loki.
   - The OpenTelemetry agent exports trace spans via gRPC directly to Grafana Tempo (`:4317`).
3. **Database Transactions:** The API queries PostgreSQL over a managed connection pool. Data is committed to an ext4 volume backed by a persistent Kubernetes `HostPath` volume.
4. **Metrics Scraping:** Prometheus scrapes the Spring Boot Actuator endpoint (`/actuator/prometheus`) every 15 seconds. If latency exceeds the 500 ms threshold or error rates rise, Alertmanager triggers alert states.

---

## 5. Security & Isolation Architecture

1. **Process Privilege:** All application containers execute as non-root user `appuser` (UID `10001`), with `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, and `drop: ["ALL"]` capabilities.
2. **Secrets Custody:** Plaintext secrets never touch Git. SOPS encrypts values using the public keys of two distinct age identities. CI verifies decryptability using ephemeral identities without storing private keys in runner environments.
3. **Supply-Chain Integrity:** Docker images are tagged with Git SHAs and pinned immutable digests. Actions workflows verify authentic release checksums for all downloaded external binaries.
