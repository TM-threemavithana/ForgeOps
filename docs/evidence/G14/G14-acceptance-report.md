# Gate G14 Acceptance Report: Advanced Platform Engineering — Policy-as-Code & Encrypted Secrets Management

| Metadata | Details |
|:---|:---|
| **Gate Identifier** | **Gate G14: Advanced Platform Engineering** |
| **System** | ForgeOps Platform Infrastructure |
| **Roles** | Principal DevSecOps Engineer, Security Architect, Kubernetes Platform Engineer |
| **Target Environment** | `kind-forgeops` (Local Kubernetes v1.34.11) |
| **Status** | **PASSED (Verified & Merged to Master)** |
| **Merge Order** | PR #49 (Kyverno Policy-as-Code) -> PR #50 (SOPS + age Encrypted Secrets) |

---

## 1. Executive Summary & Pull Request Traceability

Gate G14 establishes pre-deployment Policy-as-Code manifest validation using the official **Kyverno CLI** and declarative GitOps encrypted secrets management using **Mozilla SOPS** paired with **`age`** modern asymmetric cryptography.

All implementation and hardening was conducted across two sequentially merged pull requests with 100% passing GitHub Actions CI gates:

| Track | Pull Request | Head Commit SHA | Merge Commit SHA | Required CI Status |
|:---|:---|:---|:---|:---|
| **G14-A (Policy-as-Code)** | [PR #49](https://github.com/TM-threemavithana/ForgeOps/pull/49) | `88fe67fd348f2c3c1eb8813de12c69c99c2e5150` | `04655bf7abd86adf3fa279b4e2de43a27d74320e` | **Passed (7/7 jobs)** |
| **G14-B (SOPS + age Secrets)** | [PR #50](https://github.com/TM-threemavithana/ForgeOps/pull/50) | `71e9fe3532ddb4ca9222e3b66ab2334eb8b20809` | `83cd266fd00675eb2723bf6d27466540b7572ee9` | **Passed (7/7 jobs)** |

---

## 2. Hard Boundaries & Invariants Verification

### 2.1 Zero In-Cluster Admission Controllers
- **Status:** **ENFORCED (0 Admission Controllers / 0 Webhooks / 0 CRDs).**
- Kyverno executes strictly client-side via `kyverno apply` and `kyverno test` within pre-commit developer tooling and GitHub Actions CI runners.
- No validating or mutating webhook configurations were registered with the Kubernetes API server.
- The Kind cluster incurred 0 MB additional memory overhead and zero risk of admission webhook deadlock.

### 2.2 Zero Live Secret Migration or Modification
- **Status:** **ENFORCED (0 Live Cluster Secrets Mutated).**
- G14 secret management was conducted on an isolated, synthetic manifest (`security/sops/synthetic-secrets.enc.yaml`).
- Active credentials for PostgreSQL (`forgeops-dev`, `forgeops-gitops-rehearsal`), Prometheus, Grafana, Loki, Tempo, and Argo CD remained untouched.

### 2.3 Zero Paid Cloud Dependencies
- **Status:** **ENFORCED (0 Cloud KMS / 0 External Vaults).**
- Dual-recipient envelope encryption uses pure offline X25519 `age` keypairs without AWS KMS, GCP KMS, Azure Key Vault, or HashiCorp Vault.

### 2.4 Protected PVC Continuity (Zero Storage Degradation)
- **Status:** **100% INTACT (5 / 5 Baseline UIDs Preserved).**

| Namespace | PVC Name | Baseline UID | Post-G14 Status | Integrity |
|:---|:---|:---|:---|:---:|
| `forgeops-dev` | `postgres-storage-forgetasks-db-0` | `84853fb3-4d13-43a9-bc62-973c3be3c90c` | Bound | **MATCH** |
| `forgeops-gitops-rehearsal` | `postgres-storage-forgetasks-rehearsal-db-0` | `b5ea8ec9-47e8-4979-afdb-621f2e3c63b8` | Bound | **MATCH** |
| `forgeops-observability` | `prometheus-g09-monitoring-kube-promet-prometheus-db-...-0` | `cd64e090-2c69-49b3-a389-de5841ce06d6` | Bound | **MATCH** |
| `forgeops-observability` | `storage-loki-0` | `23468366-7394-4f2d-be1f-2a640d6f12c5` | Bound | **MATCH** |
| `forgeops-observability` | `storage-tempo-0` | `092b6655-6617-467c-b546-69e201a0ba8a` | Bound | **MATCH** |

---

## 3. Tool Integrity & Artifact Verification

All tooling downloaded in CI and developer environments is pinned to exact immutable versions and verified against authentic upstream release checksums before execution. Verification fails closed if any checksum mismatch occurs:

| Tool | Version | Architecture | Authentic SHA-256 Checksum | Verification Method |
|:---|:---|:---|:---|:---|
| **Kyverno CLI** | `v1.19.2` | `linux_x86_64` | `357eaf1df8bc24ddd5a73979fadeaae6a032e8710f11af264229756e4956bf4a` | `sha256sum -c -` against GitHub release asset |
| **Mozilla SOPS** | `v3.13.3` | `linux.amd64` | `e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b` | `sha256sum -c -` against `sops-v3.13.3.checksums.txt` |
| **age / age-keygen** | `v1.2.1` | `linux-amd64` | `7df45a6cc87d4da11cc03a539a7470c15b1041ab2b396af088fe9990f7c79d50` | `sha256sum -c -` against release tarball |

---

## 4. Track G14-A: Policy-as-Code Implementation & Results

### 4.1 Ten Implemented Security Policies

All policies reside in `security/policies/kyverno/` and enforce Kubernetes Pod Security Standards (PSS Restricted profile):

1. **`disallow-privileged-containers.yaml`**: Disallows `privileged: true` in container security contexts.
2. **`disallow-privilege-escalation.yaml`**: Mandates `allowPrivilegeEscalation: false`.
3. **`require-run-as-non-root.yaml`**: Enforces `runAsNonRoot: true`.
4. **`require-drop-all-capabilities.yaml`**: Enforces `capabilities.drop: ["ALL"]`.
5. **`require-seccomp-default.yaml`**: Mandates `seccompProfile.type: RuntimeDefault` or `Localhost`.
6. **`disallow-latest-tag.yaml`**: Rejects `:latest` tags and untagged images.
7. **`require-resource-requests-limits.yaml`**: Mandates explicit CPU/memory requests and limits.
8. **`disallow-host-namespaces.yaml`**: Blocks `hostNetwork`, `hostPID`, and `hostIPC`.
9. **`restrict-image-registries.yaml`**: Restricts images to approved registries (`ghcr.io/tm-threemavithana/*`, `docker.io/library/*`, `registry.k8s.io/*`). *(Enforces repository hostname pattern matching; does not cryptographically attest image signatures or SLSA provenance).*
10. **`require-security-labels.yaml`**: Requires mandatory metadata labels (`app.kubernetes.io/name`, `forgeops.dev/security-tier`).

### 4.2 Test Suite Outcomes

- **`kyverno test security/policies/kyverno/tests`**: 20/20 test assertions passed (10 positive, 10 negative).
- **Automated Security Runner (`scripts/test_g14_security.py`)**: 7/7 test suites passed:
  - Test 1: Tool version and availability.
  - Test 2: YAML syntax and schema validation across all 10 policies.
  - Test 3: Kyverno CLI native test suite execution (20 assertions).
  - Test 4: Positive workload enforcement (`pass-workload.yaml`).
  - Test 5: Negative workload rejections across 10 distinct failure fixtures.
  - Test 6: Helm-rendered `forgetasks-api` application workload validation (passes all 9 applicable container security policies).
  - Test 7: Error handling and strict fail-closed assertion on test mismatches.

---

## 5. Track G14-B: Encrypted Secrets Management Implementation & Results

### 5.1 Dual-Recipient Asymmetric Architecture

Repository secrets are encrypted at rest using Mozilla SOPS and `age` asymmetric encryption configured in `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: security/sops/.*\.enc\.ya?ml$
    encrypted_regex: '^(data|stringData)$'
    age: "age144mfts76hsnncvzpzutqhl9pe5vlf78dnyjev39lqtgzknyucppsg5g54v,age1g3thfc5hcd2cnsp86z8rqd7ps5a5vl4h9wq38fhcr47qr7efw5kqhz970y"
```

- **Primary Operational Identity:** `age144mfts76hsnncvzpzutqhl9pe5vlf78dnyjev39lqtgzknyucppsg5g54v` (authorized engineering and CI operations).
- **Disaster Recovery Escrow Identity:** `age1g3thfc5hcd2cnsp86z8rqd7ps5a5vl4h9wq38fhcr47qr7efw5kqhz970y` (air-gapped offline cold storage).

### 5.2 Kubernetes Secret Scope (`encrypted_regex`)

The synthetic fixture (`security/sops/synthetic-secrets.enc.yaml`) demonstrates Kubernetes Secret encryption with cleartext metadata:
- **Cleartext Metadata:** `apiVersion: v1`, `kind: Secret`, `metadata.name`, `metadata.namespace`, `type: Opaque`, and labels remain unencrypted for GitOps diffing and static policy evaluation.
- **Encrypted Payload:** Only sensitive credential values under `stringData` (`database_password`, `api_token`, `encryption_key`) are encrypted using AES-256-GCM.
- **Cryptographic MAC:** A SHA-512 MAC covers both cleartext metadata and ciphertext payload, immediately rejecting any manual file tampering.

### 5.3 Test Suite Outcomes (`scripts/test_g14_sops.py`)

6/6 automated test suites passed:
- Test 1: Tool versions (`sops v3.13.3`, `age v1.2.1`).
- Test 2: Configuration syntax and recipient validation in `.sops.yaml`.
- Test 3: Fixture structure inspection (cleartext metadata, ciphertext values, zero plaintext leaks).
- Test 4: Committed fixture decryption verification against **both intended recipient identities** (Primary: OK, Recovery: OK; zero leaks).
- Test 5: Dynamic dual-recipient generation, encryption, independent recovery, wrong-key non-zero rejection, missing-key non-zero rejection, and MAC tamper detection.
- Test 6: Repository hygiene scan (**zero private age keys found**).

---

## 6. Key Escrow & Operational Limitations

1. **In-Cluster Secret Decryption Reality:**
   - SOPS secures secrets **at rest in Git version control**.
   - Decrypted manifests applied to Kubernetes become standard Kubernetes `Secret` objects stored in `etcd`.
   - Production recommendation: Combine SOPS GitOps pipelines with in-cluster Sealed Secrets / External Secrets Operator, and enable Kubernetes API server `etcd` encryption at rest (`EncryptionConfiguration`).
2. **Key Custody in CI:**
   - Private keys (`AGE-SECRET-KEY-...`) are **strictly prohibited** from Git repositories.
   - Long-lived private keys are not stored in GitHub Actions runners. CI validates the complete cryptographic lifecycle dynamically using ephemeral keypairs and asserts committed fixture ciphertext integrity, while local engineering workstations maintain authorized offline custody.
3. **Registry Restriction vs. Provenance:**
   - The `restrict-image-registries` policy validates image hostname prefixes. It does not replace cryptographic signature verification (Cosign) or SLSA supply-chain attestations.

---

## 7. Sign-off & Recommendation

Gate G14 has met 100% of its acceptance criteria:
- **Zero data loss on permanent storage (5/5 PVCs Bound).**
- **Zero runtime admission controller overhead on Kind cluster.**
- **7/7 GitHub Actions CI jobs green across both pull requests.**
- **PR #49 and PR #50 merged sequentially with standard merge commits.**
- **Sanitized evidence archived under `docs/evidence/G14/`.**

**Gate G14 Outcome:** **PASSED**  
**Recommended Next Gate:** Proceed to Gate G15 (Full-system verification, documentation consolidation, and final capstone wrap-up).

