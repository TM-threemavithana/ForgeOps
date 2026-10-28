# SOPS & age Encrypted Secrets Management Runbook

| Metadata | Details |
|---|---|
| **Author** | Platform Engineering / DevSecOps |
| **System** | ForgeOps Secret Management (Gate G14-B) |
| **Tools** | Mozilla SOPS (`>= 3.9.0`), `age` (`>= 1.2.0`) |
| **Classification** | Operational Runbook & Disaster Recovery Procedure |
| **Scope** | Git-level Secret Encryption, Dual-Recipient Escrow, and Key Lifecycle |

---

## 1. Architectural Overview & Threat Model

In modern GitOps delivery (such as Argo CD or Flux), declaring desired state declaratively in Git creates a fundamental security dilemma: committing raw Kubernetes `Secret` objects exposes sensitive credentials (passwords, API tokens, TLS certificates) in version control.

### 1.1 The Solution: Mozilla SOPS + `age`

ForgeOps implements **Mozilla SOPS** (Secrets OPerationS) paired with **`age`** modern asymmetric cryptography:

```
[Plaintext Secret]
       │
       ▼ (SOPS generate random 256-bit AES data key)
[AES-256-GCM Payload Encryption] ──> [Encrypted Values only, cleartext YAML keys]
       │
       ├─ Encrypt Data Key with Primary age Recipient ──> [SOPS age metadata block]
       └─ Encrypt Data Key with Escrow age Recipient  ──> [SOPS age metadata block]
       │
       ▼ (Compute HMAC tree over all values + keys)
[Encrypted GitOps Manifest: *.enc.yaml] ──> Committed Safely to Git
```

### 1.2 Cryptographic Invariants

1. **Dual-Recipient Asymmetric Envelope Encryption:** Every secret manifest is encrypted against two independent `age` public keys:
   - **Primary Operational Key:** Used by DevOps/CI runners for routine updates.
   - **Disaster Recovery Escrow Key:** Held in offline cold storage for catastrophic primary key loss.
2. **Value-Only Encryption:** Kubernetes structural keys (`apiVersion`, `kind`, `metadata.name`, `metadata.namespace`) remain unencrypted to enable linting, diffing, and policy validation before decryption.
3. **MAC Integrity Protection:** A SHA-512 based MAC ensures that any manual tampering with ciphertext or cleartext keys is immediately rejected with a decryption failure.
4. **Zero Cloud Dependencies:** Entirely self-contained without AWS KMS, GCP KMS, or Azure Key Vault, maintaining the strict ForgeOps zero-cost boundary.

---

## 2. Key Lifecycle & Key Generation

### 2.1 Generating a New Keypair

Private keys must **NEVER** be generated inside the Git repository working tree or committed to Git.

```bash
# 1. Create secure local directory outside repo
mkdir -p -m 0700 ~/.forgeops/keys

# 2. Generate age keypair with restricted permissions
age-keygen -o ~/.forgeops/keys/forgeops-primary.agekey
chmod 0600 ~/.forgeops/keys/forgeops-primary.agekey

# 3. Extract public recipient key
grep "public key:" ~/.forgeops/keys/forgeops-primary.agekey | awk '{print $NF}'
# Output: age1...
```

### 2.2 Dual-Recipient Escrow Strategy

For high-reliability operations, generate an escrow keypair during a secure ceremony:

```bash
# Generate escrow keypair
age-keygen -o ~/.forgeops/keys/forgeops-escrow-recovery.agekey
chmod 0600 ~/.forgeops/keys/forgeops-escrow-recovery.agekey
```

- **Primary Key:** Distributed to authorized CI/CD runners (via GitHub Repository Secrets) and approved engineer workstations.
- **Escrow Key:** Stored offline (air-gapped USB drive in a physical vault, or split across trusted custodians using Shamir's Secret Sharing).

---

## 3. Routine Operations (Encrypt, Edit, Decrypt)

### 3.1 Repository Configuration (`.sops.yaml`)

The repository root [`.sops.yaml`](file:///c:/Project/ForgeOps/.sops.yaml) configures path regex and recipients:

```yaml
creation_rules:
  - path_regex: security/sops/.*\.enc\.ya?ml$
    age: "age144mfts76hsnncvzpzutqhl9pe5vlf78dnyjev39lqtgzknyucppsg5g54v,age1g3thfc5hcd2cnsp86z8rqd7ps5a5vl4h9wq38fhcr47qr7efw5kqhz970y"
```

### 3.2 Encrypting a New Secret

```bash
# Export the active age identity
export SOPS_AGE_KEY_FILE=~/.forgeops/keys/forgeops-primary.agekey

# Create plaintext source
cat <<EOF > /tmp/raw-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: forgeops-api-creds
  namespace: forgeops-prod
type: Opaque
stringData:
  DB_PASSWORD: "SuperSecurePassword123!"
  JWT_SECRET: "a8fbc892d18401e88c03bf4e8"
EOF

# Encrypt using .sops.yaml creation rules
sops --encrypt /tmp/raw-secret.yaml > security/sops/api-creds.enc.yaml

# Clean up plaintext immediately
rm -f /tmp/raw-secret.yaml
```

### 3.3 Editing an Encrypted Secret in Place

SOPS launches your default `$EDITOR`, decrypting in memory and re-encrypting automatically upon save:

```bash
export SOPS_AGE_KEY_FILE=~/.forgeops/keys/forgeops-primary.agekey
sops security/sops/synthetic-secrets.enc.yaml
```

### 3.4 Decrypting for Inspection or Local Testing

```bash
# Output decrypted plaintext to stdout (never redirect directly to tracked repo files)
export SOPS_AGE_KEY_FILE=~/.forgeops/keys/forgeops-primary.agekey
sops --decrypt security/sops/synthetic-secrets.enc.yaml
```

---

## 4. Key Rotation Workflow (`sops updatekeys`)

When a primary key is rotated (e.g., personnel departure or periodic 90-day rotation), SOPS supports zero-re-encryption-from-plaintext key updates:

### Step 1: Generate New Keypair

```bash
age-keygen -o ~/.forgeops/keys/forgeops-primary-v2.agekey
chmod 0600 ~/.forgeops/keys/forgeops-primary-v2.agekey
NEW_PUBLIC_KEY=$(grep "public key:" ~/.forgeops/keys/forgeops-primary-v2.agekey | awk '{print $NF}')
```

### Step 2: Update `.sops.yaml`

Update the `age:` entry in `.sops.yaml` with the new public key while keeping the escrow key:

```yaml
creation_rules:
  - path_regex: security/sops/.*\.enc\.ya?ml$
    age: "<NEW_PUBLIC_KEY>,age1g3thfc5hcd2cnsp86z8rqd7ps5a5vl4h9wq38fhcr47qr7efw5kqhz970y"
```

### Step 3: Execute `sops updatekeys`

Run `sops updatekeys` on all encrypted files using the **existing** primary key or escrow key to decrypt the data key:

```bash
export SOPS_AGE_KEY_FILE=~/.forgeops/keys/forgeops-primary.agekey

# Re-encrypt data keys with new recipient list
sops updatekeys security/sops/synthetic-secrets.enc.yaml
```

### Step 4: Verify Decryption with New Key

```bash
export SOPS_AGE_KEY_FILE=~/.forgeops/keys/forgeops-primary-v2.agekey
sops --decrypt security/sops/synthetic-secrets.enc.yaml > /dev/null && echo "Rotation Verified!"
```

---

## 5. In-Cluster Decryption Reality & Threat Boundary

> [!WARNING]
> **CRITICAL ARCHITECTURAL DISTINCTION: Git-Level vs. Cluster-Level Security**
> SOPS protects secrets **at rest in Git and CI/CD pipelines**. Once a secret is decrypted and applied to Kubernetes, it becomes a standard Kubernetes `Secret` object stored in `etcd`.

### 5.1 The Threat Gap

| State | Threat Level | SOPS Protection |
|---|---|---|
| In Git repository | Low | Encrypted with AES-256-GCM + age |
| In CI/CD Transit | Low | Decrypted only in ephemeral memory of authorized runner |
| In Cluster `etcd` | Medium / High | **None** (Base64 encoded plaintext by default) |
| In Pod Memory | Low / Medium | Mounted into `tmpfs` or environment variables |

### 5.2 Recommended Production Cluster Integrations

To maintain end-to-end encryption in Kubernetes:

1. **Automated In-Cluster Decryption Operators:**
   - **Sealed Secrets (Bitnami):** Asymmetric in-cluster decryption controller where only the cluster's controller holds the private key.
   - **External Secrets Operator (ESO):** Reconciles secrets from external vaults (HashiCorp Vault, cloud vaults) directly into memory.
   - **SOPS Operator / Argo CD SOPS Plugin:** Argo CD uses a custom plugin to decrypt SOPS manifests just-in-time during sync, ensuring plaintext is never written to disk.
2. **Kubernetes `etcd` Encryption at Rest:**
   - Enable an `EncryptionConfiguration` provider in the Kubernetes API server (e.g., `aescbc` or `kms`) so secrets are stored encrypted within `etcd`.
3. **Kubernetes RBAC Restrictions:**
   - Deny broad `secrets` read permissions: limit `kubectl get secrets` via role-based access control.
4. **CSI Secret Store Driver:**
   - Mount credentials directly into Pod filesystem memory (`tmpfs`) without creating intermediary Kubernetes `Secret` resources.

---

## 6. Disaster Recovery Runbook: Loss of Primary Key

If the primary operational private key is permanently lost or corrupted:

```bash
# 1. Retrieve escrow private key from secure vault
export SOPS_AGE_KEY_FILE=/mnt/secure-vault/forgeops-escrow-recovery.agekey

# 2. Test decryption using escrow key
sops --decrypt security/sops/synthetic-secrets.enc.yaml > /tmp/recovered-secret.yaml

# 3. Generate replacement primary key
age-keygen -o ~/.forgeops/keys/forgeops-primary-recovered.agekey
chmod 0600 ~/.forgeops/keys/forgeops-primary-recovered.agekey
NEW_PUB=$(grep "public key:" ~/.forgeops/keys/forgeops-primary-recovered.agekey | awk '{print $NF}')

# 4. Update .sops.yaml with new primary key
sed -i "s/age144mfts76hsnncvzpzutqhl9pe5vlf78dnyjev39lqtgzknyucppsg5g54v/$NEW_PUB/g" .sops.yaml

# 5. Re-encrypt with escrow key authorization
sops updatekeys security/sops/synthetic-secrets.enc.yaml

# 6. Securely wipe temporary recovery files
shred -u /tmp/recovered-secret.yaml
```

---

## 7. Automated Verification & Regression Testing

To verify the integrity and behavior of the SOPS/age infrastructure, execute the automated test suite:

```bash
python3 scripts/test_g14_sops.py
```

### Verified Test Cases:
1. **Tooling & Version Verification:** Confirms `sops >= 3.9.0` and `age >= 1.2.0`.
2. **Repository Configuration Validation:** Validates `.sops.yaml` structure and recipient regex.
3. **Repository Secret Ciphertext Inspection:** Asserts zero plaintext leaks and verifies age header integrity.
4. **End-to-End Cryptographic Lifecycle:** Dynamically generates dual-recipient keys, encrypts payload, and proves:
   - Primary key decrypts cleanly.
   - Escrow recovery key decrypts cleanly.
   - Unregistered third-party key is rejected.
   - Missing key is rejected.
   - Tampered ciphertext is rejected via MAC mismatch.
5. **Git Hygiene & Secret Leak Prevention:** Scans workspace to verify zero private keys are tracked.

