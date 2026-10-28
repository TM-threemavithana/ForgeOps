# ForgeOps Final Security & Operational Review (Gate G15)

| Metadata | Details |
|:---|:---|
| **Author** | Principal DevSecOps Engineer, Security Architect & Senior SRE |
| **Project** | ForgeOps — Self-Hosted DevOps & Platform Engineering Lab |
| **Target Cluster** | `kind-forgeops` (Local Kubernetes v1.34.11) |
| **Audit Date** | 2026-10-28 |
| **Classification** | Capstone Security Audit & Architectural Threat Assessment |
| **Status** | **VERIFIED & SECURED** |

---

## 1. Executive Summary

This security and operational audit provides an exhaustive evaluation of the ForgeOps platform across supply-chain security, identity and access management, container isolation, secret lifecycle, telemetry hygiene, and disaster recovery posture.

Operating under a strict **zero paid cloud dependency** model, ForgeOps demonstrates that enterprise-grade security controls (SLSA build provenance, CycloneDX SBOMs, Trivy vulnerability gating, Gitleaks scanning, Kyverno policy-as-code, and Mozilla SOPS asymmetric encryption) can be successfully implemented in self-hosted, local workstation environments without commercial SaaS subscriptions.

---

## 2. Supply-Chain Security & CI/CD Trust Boundaries

### 2.1 GitHub Actions Permissions & Trust Partitioning
The repository maintains strict separation of privilege across its automated workflows:
- **Default Permissions:** Root workflow declarations default to `contents: read`.
- **Privilege Escalation Barriers:** Elevated permissions (`packages: write`, `id-token: write`, `attestations: write`) are strictly confined to isolated release jobs in [`.github/workflows/publish.yml`](../../.github/workflows/publish.yml) after mandatory ancestry verification, master HEAD alignment, and successful CI status checks.
- **Workflow Input Hardening:** Shell input interpolation vulnerabilities are mitigated by mapping workflow dispatch inputs directly to environment variables (`env:`) and validating against POSIX alphanumeric regular expressions.

### 2.2 Vulnerability Gating & Secret Leak Detection
- **Trivy Container Scanning:** Evaluates OS packages and Java dependencies on every build. The pipeline strictly fails closed (`exit-code: 1`) on any unfixed **CRITICAL** or **HIGH** vulnerabilities.
- **Gitleaks Repository Audit:** Scans entire commit history on every push and pull request. Across 90 audited commits and 6.38 MB of repository data, **0 leaks** were detected.
- **Canary Leak Testing:** Verified in Gate G03 that intentional synthetic token injection immediately trips Gitleaks with a blocking exit code.

### 2.3 The Sigstore Attestation vs. Runnable Image Incident (G10 Case Study)
During the initial rollout of Gate G10-B (PR #32), a critical OCI artifact confusion incident occurred:
1. **Root Cause:** GitHub Actions `actions/attest-build-provenance@v2` generates a Sigstore SLSA provenance attestation bundle (`application/vnd.dev.sigstore.bundle.v0.3+json`) linked to the container image via `subject.digest`. When pushed to GHCR, GitHub Actions displays the attestation's OCI artifact digest in the workflow summary. An engineer inadvertently copied the attestation bundle digest into the Helm rehearsal values file instead of the container image digest.
2. **Runtime Failure:** Kubernetes scheduled the Pod, but `containerd` failed with `CreateContainerError` (`failed to apply OCI options: no command specified`) because the attestation artifact contains an empty configuration (2 bytes) and zero filesystem layers.
3. **Availability Defense:** Because Kubernetes was configured with a `RollingUpdate` strategy (`maxSurge: 1, maxUnavailable: 0`), the existing healthy Pod remained `Running (1/1)` and serving production traffic. Because Argo CD auto-sync was disabled (`automated.enabled: false`), the broken revision remained isolated without cascading mutations. **Zero downtime was experienced.**
4. **Corrective Controls Implemented:**
   - Hardened `publish.yml` to automatically resolve and output the canonical container image manifest digest via `docker buildx imagetools inspect`.
   - Added prominent workflow warning banners explicitly distinguishing runnable images from attestation bundles.
   - Created regression test [`scripts/test_publish_hardening.py`](../../scripts/test_publish_hardening.py) to assert that deployed digests resolve to runnable OCI manifests with non-empty configurations and layers.

---

## 3. Kubernetes Runtime Security & Policy-as-Code

### 3.1 Container Hardening & Pod Security Standards (PSS)
All application and database Pods strictly implement the **Pod Security Standards (Restricted profile)**:
- **Non-Root Execution:** Multi-stage Dockerfile enforces non-root UID `10001:10001`.
- **Privilege Restriction:** `allowPrivilegeEscalation: false` and `privileged: false` enforced across all workloads.
- **Linux Capabilities:** All Linux kernel capabilities are dropped (`capabilities.drop: ["ALL"]`).
- **Seccomp Isolation:** Enforces `seccompProfile.type: RuntimeDefault` on all containers.
- **Host Isolation:** Workloads are barred from host networking (`hostNetwork: false`), host process tables (`hostPID: false`), and host IPC (`hostIPC: false`).

### 3.2 Kyverno Policy-as-Code (Gate G14)
- **10 ClusterPolicies** in `security/policies/kyverno/` codify container security requirements.
- **Client-Side Enforcement:** Validation executes pre-deployment via the pinned Kyverno CLI (`v1.19.2`) in CI pipelines and developer toolchains (`kyverno apply` and `kyverno test`).
- **Zero Admission Controller Overhead:** No dynamic mutating/validating webhook controllers are installed in the Kind cluster, eliminating control-plane resource contention and bootstrap deadlock risks.
- **Registry Pattern Matching:** The `restrict-image-registries` rule enforces approved registry prefixes (`ghcr.io/tm-threemavithana/*`, `docker.io/library/*`, `registry.k8s.io/*`). *(Note: This pattern-matches hostnames and does not cryptographically attest image signatures; full signature enforcement requires Cosign/Notary).*

### 3.3 Kubernetes RBAC & ServiceAccount Isolation
- Dedicated ServiceAccounts are provisioned for `forgetasks-api`, `forgetasks-postgres`, `grafana-alloy`, and `tempo`.
- `automountServiceAccountToken: false` is configured on all workloads not requiring direct Kubernetes API communication.
- Grafana Alloy is granted read-only pod access strictly within `forgeops-gitops-rehearsal`. Negative tests confirmed Alloy is denied access to developer pods and secret objects.
- Tempo holds zero cluster-scoped node or pod inspection permissions.

---

## 4. Encrypted Secrets Management & Key Custody (SOPS + age)

### 4.1 GitOps Secret Storage Architecture
ForgeOps implements **Mozilla SOPS (`v3.13.3`)** paired with **`age` (`v1.2.1`)** asymmetric cryptography configured in [`.sops.yaml`](../../.sops.yaml):
- **Targeted Value-Only Encryption:** Enforced via `encrypted_regex: '^(data|stringData)$'`. Metadata (`apiVersion`, `kind`, `metadata.name`, `metadata.namespace`, `type`, and labels) remains cleartext to permit GitOps diffing and static policy evaluation.
- **AES-256-GCM Payload Encryption:** Sensitive credential values are encrypted with random 256-bit data keys.
- **Cryptographic MAC Integrity:** A SHA-512 MAC tree covers both ciphertext values and cleartext metadata, immediately rejecting any manual file tampering.

### 4.2 Dual-Recipient Escrow Strategy
Every encrypted secret manifest is encrypted against two independent public keys:
1. **Primary Operational Recipient (`age144...`):** Used by platform engineers and authorized automation.
2. **Disaster Recovery Escrow Recipient (`age1g3...`):** Stored in offline, air-gapped cold storage. Proved independently capable of decrypting the committed synthetic fixture without the primary key.

### 4.3 Git Hygiene & In-Cluster Decryption Reality
- **Zero Private Keys in Version Control:** Only public recipient keys (`age1...`) are recorded in Git. Private identity files are restricted to local host storage with `0600` permissions.
- **CI Key Custody Compliance:** Long-lived private keys are not stored in GitHub Actions runners. CI verifies ciphertext structure, metadata clarity, and validates the cryptographic envelope using dynamic ephemeral keypairs.
- **In-Cluster Threat Boundary:** SOPS protects secrets **at rest in Git**. Once applied to Kubernetes, secrets decrypt into standard Kubernetes `Secret` objects stored in `etcd`. In enterprise production, this should be paired with Kubernetes `etcd` encryption at rest (`EncryptionConfiguration` with KMS) or External Secrets Operator (ESO).

---

## 5. Reliability, Backup & Disaster Recovery Assessment

### 5.1 G12 SRE Resilience Verification
- **k6 Load Scenarios:** Executed 5 progressive load tests capping aggregate throughput at 20 req/s and 25 VUs. Observed **2,275 requests with 0 HTTP errors**.
- **Controlled Resilience Experiments:** Executed 5 failure injection scripts (Pod termination, CPU saturation, database severance, malformed image rollback, network latency). Demonstrated automatic recovery across all scenarios.
- **Single-Backend Concurrency Boundary:** Bounded lab tests routed traffic through a single-backend port-forward (`127.0.0.1:8082`). Multi-replica load balancing requires Ingress or Gateway routing.

### 5.2 G13 PostgreSQL Disaster Recovery Reality
- **Measured Command Times:**
  - `pg_dump` execution duration: **273 ms** (custom archive format with SHA-256 checksum).
  - `pg_restore` execution duration: **252 ms** (clean target database with `--exit-on-error`).
- **RTO Reality:** The 252 ms restore command is not the full Recovery Time Objective (RTO). The true **end-to-end API recovery RTO was 89.29 seconds**, covering database provisioning, Flyway schema validation, data restoration, API rollout, readiness probe passing, and authenticated multi-tenant smoke testing.
- **RPO Reality:** The 12-second backup freshness recorded during the drill was the execution interval between synthetic data seeding and snapshot capture. It reflects drill timing rather than an empirically achieved continuous operational RPO.
- **Local Disk Failure Risk:** Backups in the lab reside on local workstation disk storage. In enterprise production, disaster recovery archives must be replicated to geo-redundant, air-gapped object storage (e.g., AWS S3 with Object Lock or GCS Bucket Lock).

---

## 6. Observability Resource Bounds & Telemetry Hygiene

### 6.1 Telemetry Resource Budgets
All observability components run with explicit memory and CPU request/limit envelopes:
- **Prometheus:** 15-day local retention window, bounded WAL buffers.
- **Loki:** Chunk storage on local filesystem with 7-day retention sweep.
- **Tempo:** Local block storage with 24-hour trace retention.
- **Memory Safety:** Workstation limits prevent observability components from starving the host or Kind cluster.

### 6.2 Credential Redaction in Logs and Traces
- **Loki Logging:** Passwords, tokens, authorization headers, and cookie values are scrubbed at the Spring Boot Logback appender level before stdout emission.
- **OpenTelemetry Tracing:** The OTel Java agent is configured with attribute filtering to bar `Authorization` and `Cookie` headers from span tags.

---

## 7. Audit Conclusion & Compliance Status

The ForgeOps platform satisfies all operational security invariants:
1. **0 Leaked Secrets** across git history.
2. **0 CRITICAL or HIGH CVEs** in container images.
3. **0 Mutating Admission Controllers** in Kind cluster.
4. **0 Live Secrets Modified** (synthetic lab demonstration only).
5. **100% Protected PVC Continuity** (5 / 5 volumes intact with original UIDs).

