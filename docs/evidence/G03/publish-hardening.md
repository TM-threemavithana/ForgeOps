# Gate G03 Evidence — GHCR Publishing Security Hardening & Artifact Integrity

**Date:** 2026-10-24  
**Author:** Tharuka Madhuwantha Threemavithana (`158786462+TM-threemavithana@users.noreply.github.com`)  
**Role:** Principal DevOps Engineer, GitHub Actions Security Engineer & Senior Technical Reviewer  
**Status:** IMPLEMENTED AND LOCALLY VERIFIED (Pending GitHub Actions execution on master)  
**Target Workflow:** `.github/workflows/publish.yml`  
**Related Commits:** Baseline `5b70e43` (PR #1 merge)  

---

## 1. Executive Summary

This security assessment and hardening implementation addresses critical software supply chain vulnerabilities identified in the initial Gate G03 GitHub Container Registry (GHCR) publishing pipeline (`.github/workflows/publish.yml`).

The primary objective was to ensure that **only an approved, successfully tested source commit from trusted `master` history can produce a published container image**, and that **the published image artifact is cryptographically identical to the exact candidate image that underwent security scanning** (zero rebuild disparity / TOCTOU mitigation).

All identified vulnerabilities have been remediated with defensive controls, least-privilege permissions, automated ancestry and CI status checks, build-once local daemon loading, and tamper verification. A comprehensive test suite (`scripts/test_publish_hardening.py`) verified 40 distinct security invariants with 100% pass rate.

---

## 2. Identified Security Weaknesses & Remediation Matrix

| Risk ID | Security Weakness | Attack Vector / Impact | Remediation Applied |
|---|---|---|---|
| **VULN-PUB-01** | **Rebuild Disparity (TOCTOU)** | Candidate image was built twice: once for Trivy scan (`load: true`, `push: false`) and a second time for publish (`push: true`). The pushed image was NOT the artifact that passed scanning; non-deterministic layer timestamps, dependency changes, or cache drift could publish un-scanned code. | **Build Once, Scan Then Publish:** Built once with `load: true`, candidate Image ID captured, scanned by Trivy in local daemon, candidate ID re-verified before `docker push` of the exact pre-scanned tags. |
| **VULN-PUB-02** | **Workflow Input Injection** | Raw `${{ github.event.inputs.confirm }}` and `${{ github.event.inputs.git_sha }}` were interpolated directly into bash `run: |` blocks. Malicious inputs containing quotes or command separators could achieve arbitrary command execution on the runner. | **Sanitized Environment Variables:** All inputs mapped to `env:`, normalized via `xargs` and `tr`, and validated against strict POSIX regular expressions before any shell execution. |
| **VULN-PUB-03** | **Unvalidated Git Commit Input** | Workflow accepted arbitrary strings for `git_sha` (including branch names, short SHAs, or commits from unmerged feature branches or forks). | **Cryptographic Pinning & Ancestry Check:** Enforced 40-character hexadecimal regex (`^[0-9a-f]{40}$`), verified object existence with `git rev-parse`, verified ancestry with `git merge-base --is-ancestor`, and enforced matching current `origin/master` HEAD. |
| **VULN-PUB-04** | **Missing CI Status Verification** | Workflow assumed typing `PUBLISH` was sufficient authorization. A developer could trigger publication on a broken commit where tests failed or scans were red. | **Real-Time CI Verification:** Queries GitHub Actions API via `gh api` to confirm that the exact source commit has a `completed` and `success` run in `ci.yml`, and specifically validates that the mandatory `CI Gate` check succeeded. |
| **VULN-PUB-05** | **Overly Permissive GITHUB_TOKEN** | `packages: write` was present in the workflow without stage isolation or environment protection. | **Least-Privilege Scoping:** Global permissions restricted to `contents: read`. `packages: write` granted strictly to the `publish` job after all preflight validations pass. |
| **VULN-PUB-06** | **Lack of Protected Environment / Approval** | Anyone with repository write access could trigger an immediate release without peer review or gate approval. | **Protected Environment Guard:** Scoped the `publish` job to the GitHub Environment `release`, enabling repository owners to require manual review approvals and restricted branch triggers. |
| **VULN-PUB-07** | **Unsubstantiated Provenance Claims** | Workflow comments claimed "SLSA Level 2" provenance while rebuilding the image, violating provenance non-forgeability and build reproducibility. | **Accurate SLSA Attestation:** Integrated `actions/attest-build-provenance@v2` targeting the exact published SHA256 digest, paired with Trivy CycloneDX SBOM generation and artifact retention. |
| **VULN-PUB-08** | **Race Conditions on Concurrent Releases** | Multiple simultaneous `workflow_dispatch` executions could interleave tag updates or produce inconsistent digest outputs. | **Workflow Concurrency Control:** Added `concurrency: group: publish-ghcr, cancel-in-progress: false` to sequence releases safely. |

---

## 3. Architecture of the Hardened Publishing Pipeline

The hardened pipeline implements a two-job, fail-fast architecture:

```text
[ Manual workflow_dispatch ]
        │  Inputs: git_sha (40-hex), semver_tag (optional), confirm ("PUBLISH")
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Job 1: validate-release (ubuntu-latest, read-only permissions)         │
│  ├─ Step 1: Input Syntax & Confirmation Guard (regex validation)        │
│  ├─ Step 2: Checkout origin/master (fetch-depth: 0)                    │
│  ├─ Step 3: Git object existence check (git rev-parse)                 │
│  ├─ Step 4: Master branch ancestry check (git merge-base --is-ancestor)│
│  ├─ Step 5: Master HEAD alignment check (initial policy: HEAD only)    │
│  ├─ Step 6: GitHub Actions API query for ci.yml runs on target SHA     │
│  ├─ Step 7: Verification of completed + success status on master       │
│  └─ Step 8: Verification of mandatory 'CI Gate' status check           │
└────────────────────────────────────────────────────────────────────────┘
        │
        │ outputs: validated_sha, short_sha, semver_tag
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Job 2: publish (environment: release, packages:write)                  │
│  ├─ Step 1: Checkout verified commit SHA (immutable ref)               │
│  ├─ Step 2: Setup Docker Buildx                                        │
│  ├─ Step 3: Extract OCI metadata (sha-<short>, full SHA, semver)       │
│  ├─ Step 4: BUILD ONCE into local Docker daemon (load: true, push: false)│
│  ├─ Step 5: Capture Candidate Image ID (sha256:...)                    │
│  ├─ Step 6: Trivy Gate: Scan candidate image (CRITICAL & HIGH block)   │
│  ├─ Step 7: Trivy SARIF report upload to GitHub Code Scanning          │
│  ├─ Step 8: Generate CycloneDX SBOM & upload workflow artifact         │
│  ├─ Step 9: Login to GHCR (docker/login-action@v3)                     │
│  ├─ Step 10: TAMPER CHECK: verify candidate ID == pre-scan ID          │
│  ├─ Step 11: PUBLISH SAME IMAGE: docker push verified tags (no rebuild)│
│  ├─ Step 12: Capture canonical RepoDigests (ghcr.io/...@sha256:...)    │
│  └─ Step 13: Attest build provenance (actions/attest-build-provenance) │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Deep-Dive: Build-Once, Scan-Then-Publish Mechanism

### 4.1 The Rebuild Disparity Problem
In standard container workflows using `docker/build-push-action`, running `push: false` in one step and `push: true` in a later step causes Buildx to execute two independent builds. Even with build cache enabled:
- Timestamps and intermediate metadata vary across runs.
- If upstream base images or cached layers expire or mutate between steps, different artifacts are produced.
- The scan report from step 1 does not cryptographically attest to the image pushed in step 2.

### 4.2 The Solution Implemented
1. **Single Compilation & Packaging:** The candidate image is built once using `docker/build-push-action@v6` with `load: true` and `push: false`. This loads the compiled image directly into the runner's Docker daemon, tagging it with:
   - `ghcr.io/<owner>/forgetasks-api:sha-<short>`
   - `ghcr.io/<owner>/forgetasks-api:<full_sha>`
   - `ghcr.io/<owner>/forgetasks-api:<semver>` (if specified)
   - `forgetasks-api:candidate-${{ github.run_id }}` (local reference)
2. **Deterministic Identifier Capture:** The exact local image ID is recorded:
   ```bash
   CANDIDATE_ID=$(docker inspect --format='{{.Id}}' "$CANDIDATE_TAG")
   ```
3. **Pre-Push Security Scanning:** `aquasecurity/trivy-action` scans the candidate image by its local reference. Both OS packages and Java dependencies (`vuln-type: os,library`) are evaluated. If any un-exempted CRITICAL or HIGH vulnerability is detected, the scan exits with code `1`, immediately aborting the workflow before any registry connection or push occurs.
4. **Pre-Push Integrity Verification:** Immediately before publishing, the workflow inspects the candidate image ID again and asserts equality:
   ```bash
   CURRENT_ID=$(docker inspect --format='{{.Id}}' "$CANDIDATE_TAG")
   if [ "$CURRENT_ID" != "$EXPECTED_ID" ]; then
     echo "::error::Image integrity failure!"
     exit 1
   fi
   ```
5. **Direct Push of Loaded Image:** The workflow uses standard `docker push "$tag"` for each configured tag. Docker daemon pushes the exact pre-scanned layers.
6. **Immutable Digest Extraction:** The remote manifest digest returned by GHCR is extracted directly from the Docker daemon's `.RepoDigests` metadata:
   ```bash
   REPO_DIGEST=$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "$PRIMARY_TAG" | grep "^${REGISTRY_IMAGE}@" | head -n 1)
   DIGEST=$(echo "$REPO_DIGEST" | cut -d'@' -f2)
   ```

---

## 5. Vulnerability Enforcement & Policy Analysis

### 5.1 Enforcement Gate
The pipeline strictly enforces:
- **CRITICAL:** BLOCK (`exit-code: 1`)
- **HIGH:** BLOCK (`exit-code: 1`)
- **MEDIUM / LOW:** Logged to SARIF and uploaded to GitHub Code Scanning for informational monitoring.
- **Scanners:** `os,library` (scans Alpine OS packages and Maven jar dependencies).

### 5.2 Analysis of `ignore-unfixed: true`
The Trivy configuration includes `ignore-unfixed: true`.
- **Rationale:** Prevents release pipeline paralysis caused by upstream vulnerabilities for which no patched package exists in Alpine Linux or Maven Central.
- **Residual Risk:** A container image may be published containing known vulnerabilities if no upstream fix is available.
- **Compensating Controls (Defense-in-Depth):**
  1. *Non-root runtime execution:* Container enforces `USER 10001:10001`, preventing privileged container breakout.
  2. *Minimal runtime footprint:* Built on `eclipse-temurin:21-jre-alpine` with unused packages removed.
  3. *Network isolation:* Local port-binding to `127.0.0.1` only; Kubernetes NetworkPolicies under Cilium CNI restrict ingress/egress.
  4. *Scheduled Dependabot scanning:* Automated weekly scans monitor base images and dependencies for newly released fixes.
  5. *Code Scanning SARIF:* Unfixed vulnerabilities are still reported to GitHub Security tab for visibility.

---

## 6. Provenance and Software Bill of Materials (SBOM)

1. **SBOM Generation:**
   - Generated using Trivy's CycloneDX formatter (`format: cyclonedx`).
   - Output file: `forgetasks-api-sbom.cdx.json`.
   - Retained as a downloadable GitHub Actions artifact for 30 days via `actions/upload-artifact@v4`.
2. **Build Provenance Attestation:**
   - Integrated `actions/attest-build-provenance@v2`.
   - Binds the GitHub runner OIDC identity to the published image digest:
     `subject-name: ghcr.io/<owner>/forgetasks-api`
     `subject-digest: sha256:...`
   - Enables cryptographic verification using GitHub CLI:
     ```bash
     gh attestation verify oci://ghcr.io/<owner>/forgetasks-api@sha256:<digest> --owner <owner>
     ```

---

## 7. Local Verification Results

### 7.1 Automated Hardening Test Suite (`scripts/test_publish_hardening.py`)
Executed locally in WSL2 Ubuntu 24.04:

```text
============================================================
 ForgeOps G03 GHCR Publishing Security Hardening Tests
============================================================

--- Test 1: YAML Syntax and Schema ---
[PASS] publish.yml parsed as valid YAML
[PASS] Workflow name is 'Publish to GHCR'
[PASS] Trigger restricted exclusively to workflow_dispatch
[PASS] Concurrency configured: group=publish-ghcr, cancel-in-progress=false
[PASS] Global permissions restricted to read-only (contents: read)
[PASS] Both 'validate-release' and 'publish' jobs defined
[PASS] validate-release job has scoped read permissions (contents: read, actions: read; no packages)
[PASS] publish job scoped to protected 'release' GitHub Environment
[PASS] publish job has packages: write and contents: read
[PASS] publish job explicitly depends on 'validate-release'

--- Test 2: Shell Script Syntax (bash -n) ---
Found 6 shell script blocks in publish.yml
[PASS] Shell script block 1 passed bash -n syntax validation
[PASS] Shell script block 2 passed bash -n syntax validation
[PASS] Shell script block 3 passed bash -n syntax validation
[PASS] Shell script block 4 passed bash -n syntax validation
[PASS] Shell script block 5 passed bash -n syntax validation
[PASS] Shell script block 6 passed bash -n syntax validation

--- Test 3: Trusted Commit & Input Rejection Paths ---
[PASS] Rejection test: Non-PUBLISH confirmation correctly rejected (exit 1)
[PASS] Acceptance test: Exact 'PUBLISH' confirmation accepted (exit 0)
[PASS] SHA regex test 'short sha' (5b70e43...): Rejected as expected
[PASS] SHA regex test 'branch name' (master...): Rejected as expected
[PASS] SHA regex test 'injection attempt' (5b70e43; rm ...): Rejected as expected
[PASS] SHA regex test 'uppercase 40' (5B70E434313B...): Accepted as expected
[PASS] SHA regex test 'valid 40 hex' (5b70e434313b...): Accepted as expected
[PASS] SHA regex test '41 chars' (5b70e434313b...): Rejected as expected
[PASS] SHA regex test 'non-hex' (5b70e434313b...): Rejected as expected
[PASS] Semver regex test '1.0.0': Accepted as expected
[PASS] Semver regex test '0.1.0-rc.1': Accepted as expected
[PASS] Semver regex test 'v1.0.0': Rejected as expected
[PASS] Semver regex test 'latest': Rejected as expected
[PASS] Semver regex test '1.0': Rejected as expected
[PASS] Semver regex test '1.0.0+build123': Accepted as expected
[PASS] Git ancestry test: Current master HEAD (5b70e43) verified as valid ancestor of master
[PASS] Git existence test: Non-existent commit correctly rejected (exit non-zero)

--- Test 4: Build-Once, Scan-Once Integrity Logic ---
[PASS] Exactly ONE docker/build-push-action call present (build-once verified)
[PASS] Candidate image built locally with load: true, push: false
[PASS] Trivy security gate is executed BEFORE publishing to GHCR
[PASS] Trivy gate enforces blocking on CRITICAL,HIGH (exit-code: '1')
[PASS] Publish step uses 'docker push' on pre-scanned loaded image tags
[PASS] Pre-publish integrity check verifies image ID has not mutated
[PASS] Published image digest captured from Docker daemon RepoDigests

============================================================
 Summary: 40 PASSED, 0 FAILED
============================================================
All security hardening checks PASSED.
```

---

## 8. GitHub Repository Setup Instructions

Before triggering the first release, configure the following repository settings on GitHub:

### 8.1 Configure the "release" Environment
1. Navigate to **Settings** → **Environments** → **New environment**.
2. Name: `release`.
3. Under **Deployment protection rules**:
   - Check **Required reviewers** and add repository owner / designated release approvers.
   - Check **Deployment branches** and select **Selected branches** → Add `master`.
4. Click **Save protection rules**.

### 8.2 Verify Branch Protection Rules
Under **Settings** → **Branches** → Rule for `master`:
- **Require status checks to pass before merging**: Check this.
  - Required check: `CI Gate` (from `ci.yml`).
- **Require branches to be up to date before merging**: Check this.
- **Do not allow bypassing the above settings**: Check this.

### 8.3 Verify GitHub Container Registry (GHCR) Permissions
Under **Settings** → **Actions** → **General** → **Workflow permissions**:
- Select **Read and write permissions** (or grant per workflow).
- Check **Allow GitHub Actions to create and approve pull requests** (for future GitOps promotion).

---

## 9. Safe First-Publishing Procedure (Walkthrough)

Once the changes are merged into `master` via pull request and verified by the CI pipeline:

1. **Verify CI on master:** Confirm the merge commit on `master` has a passing `CI Gate` in GitHub Actions.
2. **Obtain full 40-character commit SHA:**
   ```bash
   git rev-parse origin/master
   # Example: 5b70e434313b0b7c6e05e1a11d9254dc23a13e5c
   ```
3. **Trigger Workflow Dispatch:**
   - Go to **Actions** → **Publish to GHCR** → **Run workflow**.
   - **git_sha**: `<paste 40-character commit SHA>`
   - **semver_tag**: `1.0.0` (optional)
   - **confirm**: `PUBLISH`
4. **Approve Environment Deployment:**
   - If Environment protection is enabled, approve the deployment prompt in the Actions UI.
5. **Verify Published Image:**
   - Inspect workflow summary for the published immutable SHA256 digest:
     ```bash
     docker pull ghcr.io/<owner>/forgetasks-api@sha256:<digest>
     ```
   - Verify image labels and non-root execution:
     ```bash
     docker inspect ghcr.io/<owner>/forgetasks-api@sha256:<digest> --format '{{ .Config.User }}'
     ```
