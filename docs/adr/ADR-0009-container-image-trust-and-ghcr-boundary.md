# ADR-0009: Container Image Trust Boundary and GHCR Publication

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
Continuous integration workflows on GitHub Actions present significant supply-chain security risks. Pull requests opened from untrusted branches or public forks could execute malicious code or attempt to exfiltrate container registry write tokens (`GITHUB_TOKEN` or personal access tokens) if workflows are misconfigured.

Furthermore, deploying container images using mutable tags (like `latest` or branch names) creates non-reproducible deployments where the exact contents of a running container cannot be cryptographically proven.

## Options Considered
1. **Unrestricted Workflow Permissions:** Give all PR workflows `packages: write` permissions and push images on every branch commit. Highly insecure; vulnerable to token theft on public repos.
2. **Local Image Builds Only:** Build images only on the local machine and load them via `kind load docker-image`. Safe, but fails to demonstrate enterprise CI/CD, automated vulnerability scanning, or public container registries.
3. **Strict Trust Boundary with Trusted Main Publication & Digest Pinning:** Untrusted PR checks execute in read-only sandboxes; only reviewed commits merged to `main` publish signed, versioned image digests to GitHub Container Registry (GHCR).

## Decision
Adopt a **Strict Image Trust Boundary** with **Digest-Based Promotion**:
1. **Untrusted PR Workflow Isolation:**
   - PR workflows (`pr-checks.yml`) run with default `permissions: read-all`.
   - Workflows perform compilation, unit/integration tests, Gitleaks secret scanning, Trivy dependency checks, and a scratch Docker build test.
   - **No GHCR write tokens** are granted to PR workflows; images are **never published** from pull requests or forks.
2. **Trusted Main Publication:**
   - Only commits merged to the protected `main` branch trigger the release pipeline (`release.yml`).
   - The release job explicitly requests scoped `permissions: { contents: write, packages: write }`.
   - The image is published to `ghcr.io/<owner>/forgetasks-api` tagged with the immutable Git commit SHA (`git-<sha>`).
3. **Cryptographic Digest Capture:**
   - The release job captures the immutable `sha256:...` digest directly from the GHCR registry response.
   - Deployments in Helm values reference the exact digest (`image.digest: sha256:...`) rather than any mutable tag.
4. **SBOM & Vulnerability Scanning:**
   - CI generates a Software Bill of Materials (SBOM in SPDX or CycloneDX format) and attaches it as a build artifact alongside the Trivy vulnerability report.

## Consequences & Trade-offs
### Positive:
- **Supply Chain Hardening:** Fork PRs cannot push malicious images to the registry or steal registry tokens.
- **Tamper-Proof Deployments:** Because Kind deploys by immutable SHA256 digest, the deployed code is guaranteed to match the audited commit.
- **Auditability:** Every running pod can be traced back to its specific CI build, SBOM, and Trivy scan report.

### Negative / Limitations:
- Local offline development requires using the local build path (`docker build` + `kind load docker-image`) when disconnected from the Internet.
- Extra steps in CI to extract and format the container digest.

## Verification Tests
- A test PR from a separate branch demonstrates that no image is pushed to GHCR.
- Merging to `main` produces an immutable image digest visible in GHCR package metadata.
- Helm chart template renders `image: ghcr.io/<owner>/forgetasks-api@sha256:...`.

## Reconsideration Triggers
- Introduction of Sigstore/Cosign keyless cryptographic image signing in Capstone phase.
