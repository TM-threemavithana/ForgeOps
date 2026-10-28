# ForgeOps: Technical Interview Q&A & Architecture Story Bank

This guide contains 22 realistic, deep-dive interview questions with evidence-backed answers derived directly from the ForgeOps implementation. It serves as an authoritative preparation resource for DevOps, Platform Engineering, SRE, and DevSecOps interviews.

---

## Category 1: Platform Architecture & Infrastructure-as-Code

### Q1: Why did you build ForgeOps without using cloud services like AWS or GCP?
**Answer:**
Building ForgeOps with zero cloud dependencies was an intentional architectural constraint. Relying on managed cloud services (EKS, RDS, KMS, CloudWatch) abstracts away fundamental platform mechanics—such as volume persistence, CNI routing, cgroup memory limits, TLS termination, and encryption envelopes. Furthermore, cloud environments incur ongoing costs that limit chaotic experimentation. By implementing ForgeOps on Kind, Docker, and Linux, every single component from the kernel cgroup to the GitOps reconciler is observable, auditable, reproducible, and completely free to run.

### Q2: How did you define component ownership across Terraform, Ansible, Kind, and Argo CD?
**Answer:**
We enforced a strict **single-owner-per-resource** governance rule documented in ADR-0001:
- **Kind Lifecycle:** Pinned shell scripts exclusively own the Kind Docker container nodes, network bridges, and cluster creation/deletion.
- **Terraform:** Exclusively manages local developer container fixtures and provisions the base Argo CD infrastructure. It is forbidden from deleting or modifying the Kind cluster.
- **Ansible:** Exclusively configures and hardens the separate Linux guest environment via SSH.
- **Argo CD:** Exclusively manages application workloads, namespaces, and Helm chart releases inside Kubernetes.
By defining explicit ownership, we eliminated tool collisions and configuration drift.

### Q3: What were the trade-offs of using Kind (Kubernetes in Docker) as your cluster orchestrator?
**Answer:**
Kind allows rapid, deterministic cluster spinning with pinned images (`v1.29.2`) and low memory footprints. However, there are two primary trade-offs:
1. **CNI Limitations:** Kind's default `kindnet` CNI implements host-local IPAM and iptables masquerading, but does not enforce Kubernetes `NetworkPolicy` ingress/egress filtering. We documented NetworkPolicies as architectural specifications rather than enforced runtime controls.
2. **Storage Constraints:** Storage relies on `HostPath` volumes mounted into the Docker container. If the Kind container is destroyed without backing up mounts, data is lost. We mitigated this by establishing strict PVC retention rules and an automated off-cluster disaster recovery pipeline.

---

## Category 2: Kubernetes Workloads, Storage & Networking

### Q4: How do you guarantee zero data loss on PostgreSQL during application updates?
**Answer:**
We decoupled stateful storage from stateless application lifecycles. PostgreSQL is deployed with a dedicated `PersistentVolumeClaim` backed by a retained storage class. The application pods communicate with PostgreSQL over the internal Kubernetes DNS (`postgres-service.forgeops-dev.svc.cluster.local:5432`). During application rollouts, Kubernetes uses a `RollingUpdate` strategy (`maxSurge: 1, maxUnavailable: 0`), spinning up the new replica and verifying its readiness probe before terminating the old pod. Throughout all 15 gates, our protected baseline PVC (`84853fb3-4d13-43a9-bc62-973c3be3c90c`) maintained 100% data integrity with zero UID churn.

### Q5: How did you configure container security contexts for the application?
**Answer:**
All application containers run with least privilege:
- `runAsNonRoot: true` with a dedicated UID (`10001`, `appuser`).
- `allowPrivilegeEscalation: false` to prevent setuid binary exploitation.
- `readOnlyRootFilesystem: true` with temporary in-memory `emptyDir` mounts for `/tmp`.
- `capabilities: drop: ["ALL"]` to strip all default Linux kernel capabilities.

---

## Category 3: CI/CD & GitOps Delivery

### Q6: What is the difference between your CI pipeline and your CD delivery flow?
**Answer:**
We strictly inverted the traditional CI push model to a declarative GitOps pull model:
- **GitHub Actions (CI):** Handles testing, static analysis, vulnerability scanning (Trivy), secret detection (Gitleaks), Kyverno policy validation, multi-arch Docker image builds, and pushes immutable container images tagged by Git SHA to GitHub Container Registry (GHCR). CI never touches the cluster or runs `helm upgrade`.
- **Argo CD (CD):** Continuously monitors the desired-state Git repository. When a release commit updates the Helm chart values with the new image digest, Argo CD detects the divergence and synchronizes the cluster state declaratively.

### Q7: Why did you disable Argo CD automatic synchronization in the rehearsal environment?
**Answer:**
In Gate G08, during our failed-release recovery drill, we observed that auto-sync can cause rapid reconciliation loops when a poisoned image digest or broken configuration is merged. Disabling auto-sync enforces a human-in-the-loop review step for production rehearsal, allowing operators to inspect diffs and plan rollbacks before applying changes.

---

## Category 4: Observability (Prometheus, Loki, Tempo)

### Q8: How did you implement correlated observability across metrics, logs, and traces?
**Answer:**
We unified the three pillars using OpenTelemetry and W3C standard trace propagation:
1. When an HTTP request enters the Spring Boot microservice, the OpenTelemetry Java instrumentation agent creates a trace and injects `trace_id` and `span_id` into the SLF4J MDC (Mapped Diagnostic Context).
2. The application logs formatted JSON containing the `trace_id`.
3. Grafana Alloy scrapes these logs and ships them to Loki.
4. Traces are exported via gRPC directly to Grafana Tempo.
5. In Grafana, we configured a "Trace to Logs" data source link that maps Tempo's `trace_id` to Loki queries (`{app="forgetasks-api"} |= "$${__trace.id}"`). An engineer viewing a high-latency trace in Tempo can click one button to view the exact log lines emitted during that execution.

### Q9: What metric alerts did you configure in Prometheus and Alertmanager?
**Answer:**
We defined alerts based on SRE Golden Signals:
- `HighHttpErrorRate`: Triggered when 5xx HTTP responses exceed 5% over a 2-minute sliding window.
- `ApiHighLatencyP95`: Triggered when 95th percentile latency exceeds 500 ms for 3 consecutive minutes.
- `PostgresConnectionPoolExhaustion`: Alerting when HikariCP active connections exceed 80% of pool capacity.
Alertmanager routes alerts through a staged pipeline (pending -> firing -> resolved) with deduplication and inhibition.

---

## Category 5: SRE Resilience & Chaos Engineering (Gate G12)

### Q10: How did you design your k6 load-testing scenarios without overwhelming the local machine?
**Answer:**
In Gate G12, we implemented progressive load profiles capped at 25 Virtual Users (VUs) and 20 requests/second. We targeted an explicitly bound port-forward (`localhost:8082`) directed exclusively to a disposable rehearsal service (`forgeops-sre-lab`), refusing arbitrary endpoints. Across 5 scenarios, the system processed 2,275 HTTP requests with zero errors, recording a median latency (p50) of 2.1 ms and a 95th percentile (p95) of 6.8 ms.

### Q11: Walk me through one of your controlled chaos experiments and how the system recovered.
**Answer:**
In Experiment 1, we executed a sudden termination of the active `forgetasks-api` Pod under load. The Kubernetes Deployment controller detected the replica count mismatch, scheduled a new pod on the node, initiated image pull from local cache, and waited for Spring Boot's `/actuator/health/readiness` probe.
- **Measured Recovery Time:** It took exactly **52.86 seconds** from pod deletion to reaching full two-replica readiness.
- **Zero Ingress Loss:** Because Kubernetes keeps the healthy surviving replica in the service endpoints while the new pod boots, k6 recorded zero HTTP dropped connections during the drill.

---

## Category 6: Disaster Recovery & PostgreSQL (Gate G13)

### Q12: What was your strategy for PostgreSQL backup and disaster recovery?
**Answer:**
We implemented an automated, non-destructive DR pipeline governed by `rehearse-dr.sh`:
1. **Backup Phase:** Triggers `pg_dump` on the source database in compressed custom archive format (`-Fc`), calculates a SHA-256 checksum manifest, and archives it to an isolated volume.
2. **Fresh Disposable Target:** Rather than restoring over production tables with dangerous `--clean` flags, we spin up an isolated database in a dedicated namespace (`forgeops-dr-lab`).
3. **Restoration Phase:** Executes `pg_restore` with `--exit-on-error` and strict exit-code trapping.
4. **Validation Phase:** Executes automated SQL integrity checks verifying schema migrations, relational row counts, and verifies application authentication by checking BCrypt password hashes.

### Q13: What were your measured RTO and RPO numbers in Gate G13?
**Answer:**
We distinguish low-level command durations from true business recovery:
- `pg_dump` execution duration: **273 ms**.
- `pg_restore` command execution duration: **252 ms**.
- **End-to-End Service RTO:** **89.29 seconds** (measuring total elapsed time from disaster initiation, target pod readiness, schema restoration, API startup, to healthy synthetic user authentication).
- **Drill Backup Age:** **12.00 seconds** (the time elapsed between snapshot generation and restoration during the drill). In production, true RPO is bounded by the backup cron interval.

---

## Category 7: DevSecOps, Policy-as-Code & Secrets (Gate G14)

### Q14: Why did you run Kyverno via CLI in CI rather than as an in-cluster admission controller?
**Answer:**
In-cluster dynamic admission webhooks require webhooks, TLS certificates, and persistent memory allocation. In a single-node resource-constrained local cluster, if an admission controller pod crashes or encounters memory pressure, the entire Kubernetes API server can deadlock, blocking all pod creation. By running `kyverno apply` client-side in GitHub Actions CI, we shift security left: 100% of Helm-rendered manifests are audited against 10 security policies before merging, eliminating cluster overhead while maintaining strict compliance.

### Q15: How does your SOPS + age secret encryption scheme work?
**Answer:**
We use Mozilla SOPS with `age` asymmetric encryption. We configured a dual-recipient scheme:
1. `Primary Operational Identity`: Used for day-to-day deployment.
2. `Recovery Escrow Identity`: Held offline for disaster recovery key recovery.
In `.sops.yaml`, we use `encrypted_regex: '^(data|stringData)$'`. This encrypts only secret values, leaving Kubernetes metadata, names, and labels in cleartext. This allows linters, Git diffs, and Helm validators to inspect manifest structures without exposing passwords. Zero private keys are stored in Git.

### Q16: How do you verify external tools in GitHub Actions to prevent supply-chain attacks?
**Answer:**
In our CI workflow (`ci.yml`), whenever external binaries (Kyverno, SOPS, age) are downloaded from GitHub releases, we do not trust them blindly. We compute the SHA-256 checksum of the downloaded archive and compare it against pinned, authentic release checksums. If a single byte differs, the script immediately exits with an error code, failing closed before binary execution.

---

## Category 8: Incident Response & Operational Lessons

### Q17: Can you describe a real technical failure that occurred during this project and how you solved it?
**Answer:**
During Gate G10, we encountered an operational incident where the ForgeTasks API pod crashed with `CreateContainerError`.
- **Root Cause:** A GitHub Actions workflow mistakenly copied a Sigstore OCI attestation bundle digest into the Helm release values instead of the runnable container image digest. Container runtimes cannot execute attestation manifests.
- **Blast Radius:** Contained to zero downtime because Kubernetes `RollingUpdate` prevented terminating existing pods when the new replica failed readiness, and Argo CD auto-sync was disabled.
- **Corrective Action:** We created `scripts/test_publish_hardening.py` to cryptographically inspect GHCR manifests, verifying that release digests point exclusively to runnable `application/vnd.docker.distribution.manifest.v2+json` or OCI image manifests, rejecting attestation bundles.

### Q18: What is the risk of using `pg_restore --clean --if-exists` in a database recovery script?
**Answer:**
Using `--clean` against an active or incorrectly targeted database drops existing tables before recreating them. If the restore script accidentally targets production due to an environment variable misconfiguration, or if the backup archive is corrupted mid-restore, the database is left in a dropped or partially restored state. We removed all `--clean` flags and mandated that restores must target a clean, fresh, isolated scratch database that has no pre-existing application tables.

### Q19: How did you handle credential verification in your disaster recovery rehearsal?
**Answer:**
In early test iterations, the synthetic accounts in the seed script used dummy BCrypt hashes that did not match the application's actual Spring Security BCrypt password encoder. We updated the seed generator to produce genuine BCrypt hashes compatible with Spring Security, verified using an automated authentication test that sends a POST request to `/api/v1/auth/login` and asserts HTTP 200 with a valid JWT token.

### Q20: Why do you avoid `docker system prune -a` in your development runbooks?
**Answer:**
In a local platform engineering environment running Kind, `docker system prune -a` deletes all cached container images, including the Kind node image, base JDK images, and temporary volume mounts. Rebuilding and re-downloading these images wastes bandwidth and time. Our runbooks mandate scoped container and volume pruning targeting only ephemeral test containers.

### Q21: What are the primary remaining risks or limitations in ForgeOps?
**Answer:**
The two primary limitations are:
1. **Single-Node Infrastructure:** Kind runs as a single Docker container. While excellent for local validation, it cannot model split-brain network partitions across physical hypervisors or multi-datacenter latency.
2. **Offline Key Custody:** SOPS private keys are managed locally by the operator. In an enterprise environment, this would be integrated with an external HSM or enterprise secret store (HashiCorp Vault).

### Q22: If you had to scale ForgeOps to a multi-cloud enterprise production deployment, what would you change first?
**Answer:**
First, I would replace Kind with a managed Kubernetes control plane (AWS EKS or GCP GKE) with multi-AZ node pools and an eBPF-based CNI (Cilium) to enforce live NetworkPolicies. Second, I would migrate PostgreSQL to a managed database with automated cross-region read replicas and WAL archiving (e.g., AWS Aurora or Cloud SQL). Third, I would configure Argo CD with automated progressive delivery (Argo Rollouts) using canary deployments governed by Prometheus latency analysis.
