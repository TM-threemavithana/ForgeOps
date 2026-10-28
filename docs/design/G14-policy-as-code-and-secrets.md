# ForgeOps Gate G14 — Advanced Platform Engineering: Policy-as-Code & Encrypted Secrets Management

**Document Status:** Approved Architecture & Implementation Specification  
**Author:** Principal DevSecOps Engineer, Kubernetes Security Engineer, Platform Engineer  
**Date:** 2026-10-28  
**Scope:** Gate G14 Subtracks G14-A (Kyverno Policy-as-Code) and G14-B (SOPS + age Encrypted Secrets)  
**Target Cluster:** `kind-forgeops` (Local single-node Kind cluster, Kubernetes v1.34.11)  
**Zero Paid Cloud Invariant:** 100% offline, local tooling and GitHub Actions CI  

---

## 1. Security Problems Addressed

In modern Kubernetes environments and GitOps delivery pipelines, security vulnerabilities predominantly manifest through misconfiguration, over-privileged workloads, and unencrypted credentials stored in version control:

1. **Privileged Runtimes & Container Breakouts:** Workloads executing with `privileged: true`, `allowPrivilegeEscalation: true`, or unneeded Linux capabilities can compromise container isolation, allowing kernel exploits to escape into the host operating system.
2. **Root Execution & Shared User IDs:** Containers executing as root (`runAsUser: 0` or missing `runAsNonRoot: true`) grant excessive privileges inside the container, facilitating file tampering, permission escalation, and root-level network binding.
3. **Host Namespace Leakage:** Pods sharing host network namespaces (`hostNetwork: true`), process spaces (`hostPID: true`), or IPC mechanisms (`hostIPC: true`) can eavesdrop on node traffic, intercept host signals, and snoop inter-process communication.
4. **Supply Chain & Immutability Risks:** Using mutable container tags (`:latest` or missing tags) introduces non-deterministic builds and deployment drift, while allowing arbitrary unvetted registries increases supply-chain poisoning risks.
5. **Noisy Neighbor & Resource Exhaustion (DoS):** Workloads lacking explicit CPU/memory requests and limits can consume unbounded node resources, leading to OOM kills of critical control-plane or observability components.
6. **Insecure Seccomp Profiles:** Containers executing with `Unconfined` seccomp profiles leave the full Linux system call table accessible, maximizing attack surface for kernel zero-days.
7. **Plaintext Secrets in Git:** Storing raw Kubernetes Secrets in Git repositories risks accidental leakage, credential exposure, and compliance violations.

---

## 2. Scope and Architecture Components

### G14-A: Policy-as-Code with Kyverno CLI (Pre-Deployment Validation)
- **Tooling:** Kyverno CLI (`v1.19.2`, pinned binary).
- **Execution Mode:** Static manifest validation in local pre-commit workflows, automated test suites, and GitHub Actions CI.
- **Cluster Impact:** **Zero runtime cluster footprint.** No live Kyverno admission controller or mutating/validating webhooks are installed in `kind-forgeops` at this stage. This eliminates cluster CPU/memory overhead and prevents bootstrap deadlock risks.
- **Policies Implemented (10 Distinct Security Controls):**
  1. `disallow-privileged-containers`: Enforces `securityContext.privileged = false`.
  2. `disallow-privilege-escalation`: Enforces `securityContext.allowPrivilegeEscalation = false`.
  3. `require-run-as-non-root`: Enforces `securityContext.runAsNonRoot = true`.
  4. `require-drop-all-capabilities`: Enforces `capabilities.drop: ["ALL"]`.
  5. `require-seccomp-default`: Enforces `seccompProfile.type = RuntimeDefault` or `Localhost`.
  6. `disallow-latest-tag`: Rejects `:latest` tags or unversioned container images.
  7. `require-resource-requests-limits`: Mandates explicit `resources.requests` and `resources.limits` for CPU and memory on production application workloads.
  8. `disallow-host-namespaces`: Enforces `hostNetwork: false`, `hostPID: false`, and `hostIPC: false`.
  9. `restrict-image-registries`: Restricts image repositories to approved registries (`ghcr.io/tm-threemavithana/*`, `docker.io/library/*`, etc.).
  10. `require-security-labels`: Mandates mandatory ownership/tier metadata (`app.kubernetes.io/name`, `forgeops.dev/security-tier`).
- **Policy Scoping & Safeguards:**
  - Policies are specifically scoped to application and synthetic test workloads.
  - System and monitoring workloads (such as Prometheus, Loki, Tempo, Alloy) requiring specialized host metrics or logging privileges are not misclassified as insecure.
- **Positive & Negative Test Framework:**
  - Built-in `kyverno test` test fixtures containing both accepted (`pass-*.yaml`) and rejected (`fail-*.yaml`) manifests.
  - Granular validation asserting exact rule evaluation outcomes and meaningful failure messages.

### G14-B: Encrypted Secrets with SOPS + age (GitOps Secret Storage)
- **Tooling:** Mozilla SOPS (`v3.13.3`, pinned binary) and `age` (`v1.2.1`, pinned binary).
- **Encryption Scheme:** Asymmetric cryptography using X25519 Curve25519 keys via `age`.
- **Target Data:** Synthetic, isolated secrets fixture (`security/sops/synthetic-secrets.enc.yaml`).
- **Live Infrastructure Isolation:**
  - **No modification or rotation of active operational credentials.** Existing PostgreSQL, Grafana, Argo CD, or GitHub tokens remain untouched.
  - **Zero private keys in Git.** Only public recipients (`age1...`) are recorded in `.sops.yaml`.
  - **Multi-Recipient Recovery:** Demonstration of dual-recipient encryption (Primary Operations Key + Escrow Disaster Recovery Key), allowing independent decryption if the primary key is compromised or lost.
  - **Tamper Detection:** Proving that tampering with ciphertext blocks or metadata causes immediate cryptographic integrity (MAC) verification failure.
  - **In-Cluster Decryption Reality:** Transparent documentation establishing that SOPS encryption at rest in Git addresses VCS storage exposure, but does not substitute for Kubernetes RBAC, Secrets encryption at rest in etcd, or KMS provider integration.

---

## 3. Version Compatibility Matrix

| Component | Pinned Version | Release Date | Compatibility Notes |
|:---|:---|:---|:---|
| **Kyverno CLI** | `v1.19.2` | 2026-10-20 | Pinned Linux x86_64 binary; supports `kyverno.io/v1` and `kyverno.io/v2` APIs |
| **Mozilla SOPS** | `v3.13.3` | 2026-07-23 | Pinned Linux amd64 binary; supports age, KMS, PGP, and YAML encryption |
| **age / age-keygen** | `v1.2.1` | 2024-12-18 | Standard Go implementation; secure X25519 asymmetric cryptography |
| **Kubernetes / Kind** | `v1.34.11` | Active | Target Kind single-node cluster `kind-forgeops` |
| **Java / Spring Boot** | `Java 21` / `Spring Boot 3.4.x` | Active | Application codebase runtime |

---

## 4. Resource Usage & Footprint

| Dimension | Expected Usage | Evaluation |
|:---|:---|:---|
| **Cluster CPU / Memory** | 0 mCPU, 0 MiB RAM | **Zero Impact:** Tools execute strictly client-side / CI-side; no cluster pods installed. |
| **Cluster Storage (PVCs)** | 0 PVCs allocated | **Zero Impact:** No PersistentVolumeClaims allocated. |
| **CI Execution Time** | +15 to +25 seconds | Fast binary execution in GitHub Actions runner. |
| **Disk Overhead (Repo)** | < 150 KB | Lightweight YAML policies and test fixtures. |

---

## 5. Threat Model (STRIDE)

| Threat Category | Attack Scenario | G14 Mitigation |
|:---|:---|:---|
| **Elevation of Privilege** | Attacker compromises container and abuses `allowPrivilegeEscalation` or `CAP_SYS_ADMIN` to gain root on node. | Kyverno policies `disallow-privileged-containers`, `disallow-privilege-escalation`, and `require-drop-all-capabilities` reject such pods before deployment. |
| **Information Disclosure** | Unencrypted Secret YAML committed to Git is exposed to unauthorized users or leaked via repository breach. | SOPS + age encrypts secret values at rest in Git using strong public key cryptography. |
| **Tampering** | Attacker modifies ciphertext in Git or injects malicious fields into encrypted secrets. | SOPS SHA-512 MAC tree verifies data integrity and rejects tampered files during decryption. |
| **Repudiation / Supply Chain** | Attacker overwrites a mutable container image tagged `:latest` with a backdoored build. | Kyverno policy `disallow-latest-tag` enforces immutable version tags. |
| **Denial of Service** | Rogue pod leaks memory or consumes 100% CPU, starving control plane and monitoring pods. | Kyverno policy `require-resource-requests-limits` mandates explicit CPU/memory ceilings. |
| **Host Snooping** | Pod attaches to `hostNetwork` or `hostPID` to intercept localhost cluster communication or inspect node processes. | Kyverno policy `disallow-host-namespaces` rejects host namespace sharing. |

---

## 6. Positive and Negative Security Test Plan

### Kyverno Policy Tests (`kyverno test`)
For each of the 10 policies, the test suite executes:
- **Positive Test (`pass-*.yaml`):** Validated workload manifest adhering to all security rules; asserts status `pass`.
- **Negative Test (`fail-*.yaml`):** Intentionally vulnerable workload manifest violating the specific control; asserts status `fail` with the expected policy violation message.

### SOPS + age Security Tests
- **Positive Decryption:** Encrypt synthetic secret with primary age key; verify clean decryption matches original fixture.
- **Negative Decryption (Invalid Key):** Attempt decryption using an unrelated disposable age key; verify non-zero exit code and failure.
- **Tamper Detection:** Alter one byte in ciphertext payload; verify SOPS cryptographic MAC integrity rejection.
- **Multi-Recipient Recovery Decryption:** Encrypt to both Primary and Recovery public keys; verify Recovery key alone can decrypt the payload.
- **Zero Plaintext Secret Exposure:** Verify that neither test keys nor decrypted plaintexts are written to tracked files or printed into CI logs.

---

## 7. Rollback Plan

1. **Policy-as-Code (G14-A):**
   - Because policies are evaluated client-side and in CI, rollback requires only reverting the Git commit introducing the policy file or adjusting the CI step.
   - Zero in-cluster state, webhooks, or admission controllers exist that could block cluster operations during a rollback.
2. **Encrypted Secrets (G14-B):**
   - The synthetic secrets demonstration is completely isolated from live operations (`security/sops/`).
   - If an encryption rule or key requires adjustment, the synthetic fixture can be re-encrypted or removed with zero effect on operational databases or Argo CD workloads.

---

## 8. Acceptance Criteria

- [ ] All 10 Kyverno security policies successfully validate against positive workloads and reject negative workloads via `kyverno test`.
- [ ] Automated regression test suite (`scripts/test_g14_security.py` or equivalent) executes all Kyverno and SOPS test cases with 100% success.
- [ ] GitHub Actions CI integrates Kyverno policy scanning and SOPS verification without weakening existing checks (Maven, Docker, Trivy, Gitleaks).
- [ ] SOPS encryption, decryption, tamper detection, and independent recovery key decryption verified with zero plaintext leaks.
- [ ] Zero changes to cluster-wide admission webhooks or baseline PVC UIDs.
- [ ] Architectural assessment of remaining G14 subtracks (Local Ingress, Ansible Molecule, Jenkins) documented.

---

## 9. Intentionally Excluded Capabilities

1. **In-Cluster Kyverno Admission Controller:** Installing the Kyverno mutating/validating webhook admission controller into the single-node Kind cluster is intentionally deferred to avoid pod resource contention and prevent cluster lockout during cold reboots.
2. **Live Production Credential Migration:** Existing credentials (PostgreSQL, Grafana, Argo CD) remain securely managed in Kubernetes Secrets and are not rotated or migrated during this synthetic demonstration.
3. **Cloud KMS / Cloud Key Vault Integration:** Cloud-managed key management services (AWS KMS, GCP Cloud KMS, Azure Key Vault) are excluded in compliance with the Zero Paid Cloud Invariant.
4. **Deprecated `ingress-nginx`:** The community `ingress-nginx` controller is explicitly excluded in favor of modern Gateway API or Traefik evaluation.

