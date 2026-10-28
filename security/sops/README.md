# Mozilla SOPS & age Encrypted Secrets Management (Gate G14-B)

This directory contains synthetic, encrypted-at-rest configuration manifests demonstrating GitOps secrets management using **Mozilla SOPS** and **age**.

## Architecture Overview

In a GitOps delivery workflow, committing raw Kubernetes Secrets to version control exposes credentials to unauthorized repository viewers and supply-chain leakage risks.

To mitigate this, ForgeOps uses **SOPS** with **age** asymmetric encryption:
- **Encryption at rest:** Secret values are encrypted using AES-256-GCM. Structural keys, metadata (`name`, `namespace`, `labels`), and Kubernetes resource types remain unencrypted and inspectable.
- **Dual-Recipient Asymmetric Cryptography:** Every secret is encrypted to multiple public recipients:
  1. **Primary Operational Recipient (`age1...`):** Used by platform engineers and authorized CI/CD runners for regular operations.
  2. **Disaster Recovery Escrow Recipient (`age1...`):** Stored in offline, air-gapped cold storage. Can independently decrypt all secrets if the primary key is compromised, corrupted, or lost.
- **Cryptographic MAC Integrity:** SOPS embeds a cryptographic message authentication code (MAC) tree covering both encrypted values and unencrypted metadata, preventing unauthorized tampering with encrypted YAML files.

## Recipient Configuration

As defined in the repository root [`.sops.yaml`](file:///c:/Project/ForgeOps/.sops.yaml):

```yaml
creation_rules:
  - path_regex: security/sops/.*\.enc\.ya?ml$
    age: "age144mfts76hsnncvzpzutqhl9pe5vlf78dnyjev39lqtgzknyucppsg5g54v,age1g3thfc5hcd2cnsp86z8rqd7ps5a5vl4h9wq38fhcr47qr7efw5kqhz970y"
```

> [!IMPORTANT]
> **Zero Private Keys in Version Control:** Only public recipient keys (`age1...`) are ever committed to Git. Private keys (age secret identity keys) are generated outside the repository with restricted filesystem permissions (`0600`) and stored in secure credential stores.

## Files

- **`synthetic-secrets.enc.yaml`**: Synthetic Kubernetes Secret manifest with encrypted `stringData` payload.
- **`README.md`**: Architectural and operational documentation.

## Usage Commands

### Decrypting for Verification (Offline)
```bash
export SOPS_AGE_KEY_FILE=/path/to/primary.agekey
sops --decrypt security/sops/synthetic-secrets.enc.yaml
```

### Decrypting using Recovery Key
```bash
export SOPS_AGE_KEY_FILE=/path/to/recovery.agekey
sops --decrypt security/sops/synthetic-secrets.enc.yaml
```

### Editing an Encrypted File in Place
```bash
export SOPS_AGE_KEY_FILE=/path/to/primary.agekey
sops security/sops/synthetic-secrets.enc.yaml
```

### Running Automated Verification Suite
```bash
python3 scripts/test_g14_sops.py
```

