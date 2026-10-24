# Gate G03 Evidence — GHCR Publishing Security Hardening & Artifact Integrity

**Date:** 2026-10-24
**Author:** Tharuka Madhuwantha Threemavithana (`158786462+TM-threemavithana@users.noreply.github.com`)
**Role:** Principal DevOps Engineer, GitHub Actions Security Engineer & Senior Technical Reviewer
**Status:** IMPLEMENTED AND LOCALLY VERIFIED (Pending post-incident 1.0.1 verification on master)
**Target Workflow:** `.github/workflows/publish.yml`
**Related Commits:** Baseline `5b70e43`, First Release `995a929`, Fix Branch `g03-registry-digest-fix`

---

## 1. Executive Summary

This security assessment and hardening implementation addresses critical software supply chain vulnerabilities identified in the initial Gate G03 GitHub Container Registry (GHCR) publishing pipeline (`.github/workflows/publish.yml`), including the post-push registry digest resolution failure observed during production release run `40121874920`.

The primary objective was to ensure that **only an approved, successfully tested source commit from trusted `master` history can produce a published container image**, and that **the published image artifact is cryptographically identical to the exact candidate image that underwent security scanning** (zero rebuild disparity / TOCTOU mitigation).

All identified vulnerabilities have been remediated with defensive controls, least-privilege permissions, automated ancestry and CI status checks, build-once local daemon loading, authoritative GHCR registry manifest digest verification via `docker buildx imagetools inspect`, multi-tag consistency assertion, and mandatory SLSA build provenance attestation. A comprehensive test suite (`scripts/test_publish_hardening.py`) verified 70 distinct security invariants with 100% pass rate.

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
| **VULN-PUB-09** | **Dispatch from Non-Master Branches** | `workflow_dispatch` can be invoked from any branch where the file exists. If run on a feature branch, it could publish untested code. | **Branch Execution Guard:** Explicitly checks `$WORKFLOW_REF == "refs/heads/master"`. Dispatches from feature branches, PR refs, or tags are immediately blocked. |
| **VULN-PUB-10** | **Invalid Docker Tag Format ('+' character)** | Standard SemVer allows build metadata (e.g. `1.0.0+build123`), but OCI/Docker container tag syntax forbids `+`, causing downstream push/build failures. | **Docker Tag Format Guard:** Rejects `+` with an explicit diagnostic error and validates against strict container-compatible SemVer regex. |
| **VULN-PUB-11** | **Fragile Local Daemon RepoDigests & Case Mismatch** | Post-push digest lookup relied on local Docker daemon `docker inspect .RepoDigests` with exact case match. OCI lowercase normalization caused digest resolution failure in Actions run `40121874920`, blocking digest output and attestation despite successful push. | **Authoritative Registry Verification & Canonical Lowercase:** Converted image reference to canonical lowercase reference (`canonical_image`), replaced daemon `.RepoDigests` with `docker buildx imagetools inspect`, validated all tags resolve to identical digest, verified remote manifest config matches candidate ID, and enforced mandatory SLSA attestation (no `continue-on-error`). |

---

## 3. Architecture of the Hardened Publishing Pipeline

The hardened pipeline implements a two-job, fail-fast architecture:

```text
[ Manual workflow_dispatch ]
        │  Inputs: git_sha (40-hex), semver_tag (optional), confirm ("PUBLISH")
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Job 1: validate-release (ubuntu-latest, read-only permissions)         │
│  ├─ Step 1: Trigger Ref (refs/heads/master) & Docker SemVer Validation │
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
6. **Authoritative Immutable Digest Verification:** Instead of fragile local daemon `.RepoDigests` lookups (which failed due to case mismatch in run `40121874920`), the workflow directly queries the GHCR registry using `docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$tag"`. It iterates across every published tag, validates that each tag resolves to an identical full 64-character sha256 digest, and verifies that the remote manifest configuration digest matches the local scanned candidate image ID:
   ```bash
   TAG_DIGEST=$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$tag" 2>&1 | tr -d '[:space:]')
   ```

---

## 5. Vulnerability Enforcement & Policy Analysis

### 5.1 Enforcement Gate
The pipeline strictly enforces:
- **CRITICAL:** BLOCK (`exit-code: 1`)
- **HIGH:** BLOCK (`exit-code: 1`)
- **MEDIUM / LOW:** Logged to SARIF and uploaded to GitHub Code Scanning for informational monitoring.
- **Scanners:** `os,library` (scans Alpine OS packages and Maven jar dependencies).

### 5.2 Analysis of `ignore-unfixed: true` & Code Scanning SARIF Scope
Both the blocking gate step and the SARIF report generation step configure `ignore-unfixed: true`.
- **Rationale:** Prevents release pipeline paralysis caused by upstream vulnerabilities for which no patched package exists in Alpine Linux or Maven Central.
- **Direct Impact on GitHub Code Scanning:** Because `ignore-unfixed: true` is set on the Trivy SARIF generation step, **unfixed vulnerabilities are explicitly excluded from the SARIF upload and will NOT appear as alerts in GitHub Code Scanning**. Code Scanning alerts are strictly reserved for actionable (fixable) CRITICAL and HIGH vulnerabilities.
- **Residual Risk:** A container image may be published containing known vulnerabilities without an available upstream fix, and these unfixed CVEs will not trigger Code Scanning alerts.
- **Where Unfixed Vulnerabilities Can Be Inspected:**
  1. *CycloneDX SBOM:* A complete bill of materials is generated from the candidate image (`forgetasks-api-sbom.cdx.json`) and retained as a workflow artifact, allowing offline vulnerability lookup (e.g. via `trivy sbom` or Dependency-Track).
  2. *Local / Manual Trivy Scans:* Running `trivy image --ignore-unfixed=false <image>` reveals all known unfixed vulnerabilities.
  3. *Dependabot:* Continues monitoring base images and Maven dependencies weekly for newly published fixes.
- **Compensating Runtime Controls (Defense-in-Depth):**
  1. *Non-root runtime execution:* Container enforces `USER 10001:10001`, preventing privileged container breakout.
  2. *Minimal runtime footprint:* Built on `eclipse-temurin:21-jre-alpine` with unused packages removed.
  3. *Network isolation:* Local port-binding to `127.0.0.1` only; Kubernetes NetworkPolicies under Cilium CNI restrict ingress/egress.

---

## 6. Provenance and Software Bill of Materials (SBOM)

1. **SBOM Generation:**
   - Generated using Trivy's CycloneDX formatter (`format: cyclonedx`).
   - Output file: `forgetasks-api-sbom.cdx.json`.
   - Retained as a downloadable GitHub Actions artifact for 30 days via `actions/upload-artifact@v4`.
2. **Build Provenance Attestation:**
   - Integrated `actions/attest-build-provenance@v2`.
   - Mandatory enforcement: `continue-on-error: true` removed; failure blocks release immediately.
   - Binds the GitHub runner OIDC identity to the canonical lowercase image name and verified manifest digest:
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
[PASS] validate-release defines required output: validated_sha
[PASS] validate-release defines required output: short_sha
[PASS] validate-release defines required output: semver_tag
[PASS] validate-release defines required output: canonical_image
[PASS] publish job scoped to protected 'release' GitHub Environment
[PASS] publish job has packages: write, contents: read, attestations: write, and id-token: write
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
[PASS] Trigger ref test 'refs/heads/master': Accepted as expected
[PASS] Trigger ref test 'refs/heads/feature/branch': Rejected as expected
[PASS] Trigger ref test 'refs/heads/g03-publish-hardening': Rejected as expected
[PASS] Trigger ref test 'refs/pull/1/merge': Rejected as expected
[PASS] Trigger ref test 'refs/tags/v1.0.0': Rejected as expected
[PASS] Rejection test: Non-PUBLISH confirmation correctly rejected (exit 1)
[PASS] Acceptance test: Exact 'PUBLISH' confirmation accepted (exit 0)
[PASS] SHA regex test 'short sha' (5b70e43...): Rejected as expected
[PASS] SHA regex test 'branch name' (master...): Rejected as expected
[PASS] SHA regex test 'injection attempt' (5b70e43; rm ...): Rejected as expected
[PASS] SHA regex test 'uppercase 40' (5B70E434313B...): Accepted as expected
[PASS] SHA regex test 'valid 40 hex' (5b70e434313b...): Accepted as expected
[PASS] SHA regex test '41 chars' (5b70e434313b...): Rejected as expected
[PASS] SHA regex test 'non-hex' (5b70e434313b...): Rejected as expected
[PASS] Docker Semver test '1.0.0': Accepted as expected
[PASS] Docker Semver test '0.1.0-rc.1': Accepted as expected
[PASS] Docker Semver test '2.0.0-beta.2': Accepted as expected
[PASS] Docker Semver test '1.0.0+build123': Rejected (forbidden/invalid) as expected
[PASS] Docker Semver test '1.0.0+20130313144700': Rejected (forbidden/invalid) as expected
[PASS] Docker Semver test 'v1.0.0': Rejected (forbidden/invalid) as expected
[PASS] Docker Semver test 'latest': Rejected (forbidden/invalid) as expected
[PASS] Docker Semver test '1.0': Rejected (forbidden/invalid) as expected
[PASS] Docker Semver test '1.0.0.0': Rejected (forbidden/invalid) as expected
[PASS] Git ancestry test: Current master HEAD (995a929) verified as valid ancestor of master
[PASS] Git existence test: Non-existent commit correctly rejected (exit non-zero)

--- Test 4: Build-Once, Scan-Once Integrity Logic ---
[PASS] Exactly ONE docker/build-push-action call present (build-once verified)
[PASS] Candidate image built locally with load: true, push: false
[PASS] Trivy security gate is executed BEFORE publishing to GHCR
[PASS] Trivy gate enforces blocking on CRITICAL,HIGH (exit-code: '1')
[PASS] Publish step uses 'docker push' on pre-scanned loaded image tags
[PASS] Pre-publish integrity check verifies image ID has not mutated

--- Test 5: Authoritative Registry Digest & Provenance Attestation Logic ---
[PASS] Workflow uses authoritative 'docker buildx imagetools inspect' for registry manifest digest retrieval
[PASS] Fragile local Docker daemon 'RepoDigests' lookup completely removed
[PASS] Canonical lowercase image normalization implemented in validate-inputs
[PASS] metadata-action references canonical lowercase image output
[PASS] Rejection test: Missing/empty registry digest correctly rejected (exit 1)
[PASS] Rejection test: Registry query failure correctly rejected (exit 1)
[PASS] Digest format test 'valid full sha256': Accepted as expected
[PASS] Digest format test 'truncated digest': Rejected as expected
[PASS] Digest format test 'missing sha256 prefix': Rejected as expected
[PASS] Digest format test 'uppercase hex': Rejected as expected
[PASS] Digest format test 'invalid prefix sha1': Rejected as expected
[PASS] Digest format test 'invalid non-hex characters': Rejected as expected
[PASS] Rejection test: Mismatched image-tag digests correctly rejected (exit 1)
[PASS] Acceptance test: Consistent digests across multiple tags accepted (exit 0)
[PASS] Acceptance test: Remote manifest config digest matches candidate ID (exit 0)
[PASS] Rejection test: Remote config digest mismatch correctly rejected (exit 1)
[PASS] Attestation subject-name uses canonical lowercase image reference
[PASS] Attestation subject-digest uses verified registry manifest digest
[PASS] Mandatory attestation verified: 'continue-on-error: true' removed; failure blocks release

============================================================
 Summary: 70 PASSED, 0 FAILED
============================================================
All security hardening and registry digest checks PASSED.
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
   - **semver_tag**: `1.0.1` (or leave blank for SHA-only tagging; do NOT reuse `1.0.0`)
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

---

## 10. First Production Release Incident (Run 40121874920) & Root Cause Analysis

### 10.1 Incident Context
On October 24, 2026, the first controlled release to GHCR was dispatched against master commit `995a92954000f987736875be6881912a74b8b07e` via GitHub Actions Run `40121874920`.

The workflow executed as follows:
1. **Preflight validations:** Successfully validated trigger ref (`refs/heads/master`), `PUBLISH` confirmation, 40-character hex SHA syntax, master git ancestry, HEAD alignment, and clean `CI Gate` passing status on master.
2. **Environment Protection:** Successfully paused for required approver review in the `release` environment and proceeded upon explicit authorization.
3. **Single Build & Trivy Scan:** Built candidate image once into the local Docker daemon, verified candidate ID, scanned and passed Trivy CRITICAL and HIGH gates with 0 vulnerabilities.
4. **Push to GHCR:** Successfully pushed all three tags to GHCR:
   - `ghcr.io/tm-threemavithana/forgetasks-api:sha-995a929`
   - `ghcr.io/tm-threemavithana/forgetasks-api:995a92954000f987736875be6881912a74b8b07e`
   - `ghcr.io/tm-threemavithana/forgetasks-api:1.0.0`
5. **Registry Publication:** The registry successfully received and stored the image under authoritative manifest digest:
   `sha256:3d297bba979079d38ee0f91b87c07648676e2f4adb26955c90e029f3dcfbcaba`
6. **Failure Point:** Step `Record and verify published image digest` aborted with exit code 1:
   `Error: Could not determine published repository digest from Docker daemon.`
7. **Downstream Impact:** The workflow terminated before Step 13 (`Attest build provenance`). While the container images were published to GHCR, no SLSA provenance attestation was created, leaving the first release in an incomplete state.

### 10.2 Root Cause Analysis
The failure was caused by two compounding design flaws in the digest retrieval step:
1. **Repository Name Case-Sensitivity Mismatch:**
   - In GitHub Actions, `${{ github.repository }}` returned `TM-threemavithana/forgetasks-api` (preserving the GitHub username capitalization).
   - The OCI image reference specification and `docker/metadata-action` automatically downcase image repository paths to lowercase (`ghcr.io/tm-threemavithana/forgetasks-api`).
   - The digest extraction script executed:
     `REPO_DIGEST=$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "$PRIMARY_TAG" | grep "^${REGISTRY_IMAGE}@" | head -n 1)`
     Because `${REGISTRY_IMAGE}` contained uppercase `TM-threemavithana`, the grep search pattern `^ghcr.io/TM-threemavithana/forgetasks-api@` matched nothing in `.RepoDigests` (which contained `ghcr.io/tm-threemavithana/forgetasks-api@...`), resulting in an empty digest string.
2. **Fragile Reliance on Docker Daemon `.RepoDigests`:**
   - `.RepoDigests` is an internal Docker daemon cache property populated only after specific client-side push interactions. It is not an authoritative registry confirmation.
   - Relying on local daemon inspect for supply-chain digest confirmation is susceptible to daemon caching quirks, Buildx multi-backend differences, and client-side formatting inconsistencies.

### 10.3 Implemented Remediation
1. **Canonical Lowercase Normalization:**
   In `validate-release`, computed and exported `CANONICAL_IMAGE="$(echo "${REGISTRY}/${IMAGE_NAME}" | tr '[:upper:]' '[:lower:]')"`, guaranteeing lowercase OCI conformity across all workflow steps (`docker/metadata-action`, `imagetools`, and `attest-build-provenance`).
2. **Authoritative Registry Verification with `docker buildx imagetools`:**
   Completely removed `docker inspect .RepoDigests`. The step now queries GHCR directly using:
   `docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$tag"`
3. **Comprehensive Tag Consistency Check:**
   Every published tag (`sha-<short>`, `<full-sha>`, `<semver>`) is queried directly from GHCR. The workflow strictly asserts that every tag resolves to the identical 64-character sha256 manifest digest.
4. **Scanned Candidate to Remote Manifest Matching:**
   For single-platform manifests, the workflow inspects the raw OCI manifest (`docker buildx imagetools inspect --raw "$tag"`) and verifies that `config.digest` exactly matches the pre-push scanned candidate image ID (`$EXPECTED_CONFIG_ID`).
5. **Mandatory Provenance Attestation:**
   Removed `continue-on-error: true` from `attest-build-provenance`. The attestation step now binds to the canonical lowercase image name and verified registry manifest digest. Any attestation generation or signing error causes release failure.

---

## 11. Versioning Safety & Next Release Procedure (1.0.1)

### 11.1 Registry Tag Immutability Policy
During run `40121874920`, tag `1.0.0` was successfully written to GHCR pointing to manifest `sha256:3d297bba979079d38ee0f91b87c07648676e2f4adb26955c90e029f3dcfbcaba`.

**Strict Rule:** To prevent breaking supply-chain immutability and client-side Docker layer caches, **do not overwrite or delete the existing `1.0.0` tag in GHCR**.

### 11.2 Next Release Procedure (v1.0.1)
Once this fix branch (`g03-registry-digest-fix`) is reviewed, merged into `master`, and passes CI:

1. **Verify Master CI Gate:** Confirm the merge commit on `master` has completed all `ci.yml` checks.
2. **Obtain Commit SHA:**
   ```bash
   git rev-parse origin/master
   ```
3. **Trigger Workflow Dispatch with Version Bump:**
   - **git_sha**: `<paste 40-character commit SHA from master>`
   - **semver_tag**: `1.0.1` (do NOT reuse `1.0.0`)
   - **confirm**: `PUBLISH`
4. **Approve Release Environment:** Approve the deployment in GitHub Actions.
5. **Verify Verification & Provenance:**
   Confirm that all tags (`sha-<short>`, `<full-sha>`, `1.0.1`) resolve to the same manifest digest and that the SLSA attestation is successfully written and signed:
   ```bash
   gh attestation verify oci://ghcr.io/tm-threemavithana/forgetasks-api@sha256:<verified-digest> --owner tm-threemavithana
   ```
