# ADR-0006: Secret Hygiene and Out-of-Band Local Injection

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
Accidental credential leakage to public Git repositories (database passwords, API tokens, SSH keys, TLS certificates) is one of the most critical security vulnerabilities in software engineering. When practicing GitOps with Argo CD, committing Kubernetes `Secret` manifests containing base64-encoded plaintext passwords directly into Git breaches standard security hygiene.

ForgeOps requires a strict secret management architecture that ensures zero credentials enter the Git repository while enabling reliable local operation.

## Options Considered
1. **Committed Plaintext / Base64 Kubernetes Secrets:** Trivial to implement, but leaks credentials immediately to Git history. Unacceptable.
2. **HashiCorp Vault / External Secrets Operator (ESO):** Industry standard, but introduces substantial memory and operational overhead on a resource-constrained 16 GB laptop.
3. **Out-of-Band Local Secret Injection with `existingSecretName`:** Credentials are generated locally using cryptographically secure randomness, stored in a restricted host directory (`~/.config/forgeops/secrets/`, permissions 0700/0600), and injected directly into Kubernetes namespaces before Argo CD synchronizes application charts.

## Decision
Adopt **Out-of-Band Local Secret Injection**:
1. **Local Generation & Isolation:**
   - Secrets are generated via `scripts/check/generate-secrets.sh` and stored on the operator filesystem under `~/.config/forgeops/secrets/`.
   - `.env.local` is used for Docker Compose and is strictly ignored by `.gitignore`.
2. **Kubernetes Decoupling:**
   - Local bootstrap scripts provision standard Kubernetes `Secret` resources (`forgetasks-db-secret`) directly into the target namespaces (`forgeops-dev`, `forgeops-staging`).
   - Helm charts manage only Deployments, Services, and ConfigMaps, referencing database credentials via `existingSecretName: forgetasks-db-secret`.
   - Argo CD manifest trees in Git contain **zero secret definitions**.
3. **Continuous Secret Auditing:**
   - Gitleaks runs in pre-commit hooks and GitHub Actions PR workflows to block commits containing high-entropy tokens or credentials.
   - Application logs and Actuator endpoints are strictly sanitized to prevent credential exposure.
4. **Advanced Extension (Deferred):**
   - SOPS + age encryption or Sealed Secrets is documented as a Capstone option (G14), requiring tested recovery keys before deployment.

## Consequences & Trade-offs
### Positive:
- **Zero Leak Risk:** Plaintext secrets never enter Git, pull requests, or container image layers.
- **Low Resource Usage:** Avoids running heavy secrets engines like Vault inside the local Kind cluster.
- **GitOps Purity:** Git manages application topology and configuration; environmental secrets remain decoupled.

### Negative / Limitations:
- Cluster resets require re-running the secret injection script before unpausing Argo CD application synchronization.
- Manual secret rotation requires updating the pre-existing Kubernetes Secret and restarting application pods.

## Verification Tests
- Gitleaks scan passes cleanly across all branches and commits.
- Helm template rendering (`helm template platform/charts/forgetasks`) produces manifests with no plaintext passwords.
- Application pod environment variables receive DB credentials from Secret keys without logging them on startup.

## Reconsideration Triggers
- Introduction of team-based multi-user workflows where declarative encrypted secrets in Git (SOPS+age) become necessary.
