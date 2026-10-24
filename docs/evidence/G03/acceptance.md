# Gate G03 Acceptance Report — GitHub Actions CI/CD, Supply Chain Security & GHCR Publishing

**Date:** 2026-10-25
**Evaluator:** Tharuka Madhuwantha Threemavithana (`157876462+TM-threemavithana@users.noreply.github.com`)
**Role:** Principal DevOps Engineer, CI/CD Architect & Container Security Reviewer
**Gate:** G03 — Local & GitHub Actions CI Pipelines, Trust Boundaries and GHCR Publishing
**Status:** PASSED — VERIFIED
**Repository Working Tree:** Clean at verification
**Execution Profile:** Core Profile (Local-First, Zero Cloud Dependencies)

---

## 1. Executive Summary

Gate G03 implements a secure, layered CI/CD system that separates untrusted CI (triggered on
push/PR to master) from a manually controlled, approver-gated CD publishing workflow. All locally
verifiable steps and GitHub Actions CI/CD workflows have been executed and verified.

Following the merge of PR #13 (commit `7adeec6fddda8c2e15f2f390e99f56c5b35d2fe2`), master CI run `40127142460` passed all validation checks including Maven verify (43 tests, JaCoCo ≥80%), Docker non-root build validation, Gitleaks secret detection, and Trivy security scanning. The required `ci-gate` status check succeeded.

The production release workflow was subsequently executed in Run `40127622068`, successfully publishing version `1.0.1` to GitHub Container Registry (GHCR) under verified digest `sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691` with validated CycloneDX 1.6 SBOM and cryptographically verified SLSA build provenance.

Key deliverables:

1. **CI Workflow** (`.github/workflows/ci.yml`): Triggers on push and PR to master. Runs
   Maven verify (43 tests, JaCoCo ≥80%), Docker image build validation, non-root user check,
   Trivy CRITICAL scan with SARIF upload to GitHub Code Scanning, and Gitleaks secret scan.
   All jobs gate on the `ci-gate` summary job — the required status check for branch protection.

2. **Publish Workflow** (`.github/workflows/publish.yml`): `workflow_dispatch` ONLY. Requires
   manual git SHA input, a semver tag (optional), and the literal string "PUBLISH" as a
   confirmation guard. Runs Trivy scan (zero CRITICAL/HIGH unfixed CVEs at configured threshold)
   before any push; on pass builds and pushes to GHCR with signed SLSA build provenance attestation
   and CycloneDX SBOM. Image is referenced by immutable SHA256 digest.

3. **Dependabot** (`.github/dependabot.yml`): Monitors GitHub Actions, Maven, and Docker
   base images weekly. All updates target master via pull request — never auto-merged.

4. **Local CI Script** (`scripts/verify_g03_local.sh`): Replicates the GitHub Actions CI
   locally including Maven verify, Docker build, non-root verification, and optional Trivy/
   Gitleaks/actionlint checks.

5. **Trust Boundary Enforced**: No workflow pushes to GHCR on PR or push events. The
   publish workflow requires `packages:write` permission granted only to the triggering actor
   and protected environment approval.

6. **Supply Chain Controls**: Action versions pinned to stable major tags (v4, v3, v6).
   Dependabot monitors these for updates. Signed SLSA build provenance attached to published
   images. CycloneDX SBOM generated alongside each push.

---

## 2. Environment Baseline

- **Host OS:** Windows 11 Enterprise (WSL2 Ubuntu 24.04.1 LTS)
- **Java:** 21.0.12.1 (Eclipse Temurin)
- **Maven Wrapper:** 3.9.9
- **Docker Engine:** 29.5.3
- **Trivy:** (optional local; enforced in CI runner)
- **actionlint:** (optional local; documented)
- **GitHub Actions Runner:** `ubuntu-latest`
- **GitHub CLI:** `gh` 2.60+

---

## 3. Acceptance Tests

### A-301: Untrusted PR workflow (read-only permissions)

| Item | Requirement | Evidence |
|---|---|---|
| Trigger | push and pull_request to master | `.github/workflows/ci.yml` L12–17 |
| Permissions | `contents: read`, `security-events: write` | `.github/workflows/ci.yml` L19–22 |
| No GHCR push | CI never calls `docker/login-action` or `build-push-action` with `push: true` | Confirmed by file inspection |
| Build and test | `./mvnw clean verify -B -e` with JaCoCo gate | Job `build-and-test` (Run `40127142460`) |
| Non-root check | Docker inspect verifies UID 10001 | Job `docker-build-validate` (Run `40127142460`) |
| Trivy gate | Zero CRITICAL unfixed CVEs enforced with `exit-code: 1` | Job `trivy-scan` (Run `40127142460`) |
| Gitleaks | Full history scan on each run (`fetch-depth: 0`) | Job `gitleaks-scan` (Run `40127142460`) |
| Required status | `ci-gate` job aggregates all results | `.github/workflows/ci.yml` L200+ (Run `40127142460`: success) |

### A-302: Trusted release to GHCR by SHA256 (Hardened)

| Item | Requirement | Evidence |
|---|---|---|
| Trigger | `workflow_dispatch` only | `.github/workflows/publish.yml` |
| Concurrency | Single release execution | `publish-ghcr`, `cancel-in-progress: false` |
| Input sanitization | No shell interpolation; regex guards | `validate-release` step 1 |
| Confirmation guard | Input must equal literal "PUBLISH" | `validate-release` step 1 |
| SHA format validation | Full 40-character hexadecimal SHA | `validate-release` step 1 regex check |
| Repository existence | Object exists in repository database | `validate-release` step 2 (`git rev-parse`) |
| Trusted history | Must be ancestor of `origin/master` | `validate-release` step 2 (`git merge-base`) |
| Head alignment | Must match current `origin/master` HEAD | `validate-release` step 2 HEAD check |
| CI run verification | Real-time query of `ci.yml` run | `validate-release` step 3 (`gh api`) |
| CI Gate check | Mandatory `CI Gate` job completed:success | `validate-release` step 3 (`gh api`) |
| Protected environment | Approval required via `release` environment | `publish` job `environment: release` (Run `40127622068`) |
| Build-once integrity | Build once, load locally, zero rebuild | `publish` step 4 (`load: true`, `push: false`) |
| Tamper verification | Candidate Image ID verified pre/post scan | `publish` step 5 & 10 (`docker inspect`) |
| Pre-push Trivy gate | Zero CRITICAL or HIGH unfixed CVEs at configured threshold | `publish` step 6 (`exit-code: 1`, `severity: CRITICAL,HIGH`) |
| Digest verification | Authoritative GHCR query (`imagetools`) across all tags | `publish` step 12 (`sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691`) |
| Config ID match | Remote config digest matches scanned candidate ID | `publish` step 12 (`buildx imagetools inspect --raw`) |
| Provenance | Mandatory SLSA Build Provenance attestation | `publish` step 13 (`actions/attest-build-provenance@v2`, no continue-on-error) |
| SBOM | CycloneDX SBOM generated and retained | `publish` step 8 & 9 (Trivy + `upload-artifact@v4`) |
| Scoped permissions | `packages:write` scoped strictly to `publish` | Workflow job permission blocks |

### A-303: Local CI counterpart

| Item | Requirement | Evidence |
|---|---|---|
| Script exists | `scripts/verify_g03_local.sh` | Present, executable |
| Maven verify | Executes `./mvnw clean verify -B -q` | Script step 2 |
| Docker build + non-root check | Builds image, inspects user | Script step 3 |
| Trivy check | Optional; warns if not installed | Script step 4 |
| Gitleaks check | Optional; warns if not installed | Script step 5 |
| actionlint | Optional; warns if not installed | Script step 6 |
| Make target | `make ci-local` delegates to script | Makefile G03 targets |

---

## 4. Local Verification Command Log

All commands were executed in WSL Ubuntu (`/mnt/c/Project/ForgeOps`):

```
$ ./scripts/verify_g03_local.sh --skip-trivy
============================================================
 ForgeOps G03 Local CI Verification
 2026-10-24T15:22:21Z
 Repo: /mnt/c/Project/ForgeOps
============================================================
[INFO] Checking required toolchain...
[PASS] Java 21 detected: openjdk version "21.0.12.1"
[PASS] Maven available
[PASS] Docker Engine: 29.5.3
[INFO] Running Maven clean verify (unit + integration tests + JaCoCo)...
  Tests run: 43, Failures: 0, Errors: 0, Skipped: 0
  JaCoCo instruction coverage: 94.09%  (gate >=80%) — PASS
  JaCoCo branch coverage:      91.23%  (gate >=80%) — PASS
[PASS] Maven verify passed — all tests green, JaCoCo gate satisfied
[INFO] Building Docker image locally (no push)...
  Image: forgetasks-api:g03-local-ci-1792855551
  Builder: eclipse-temurin:21-jdk-alpine (CACHED)
  Runtime: eclipse-temurin:21-jre-alpine (CACHED)
  Manifest: sha256:b570fe345e2dee589adcbe7da46c2d48578b1fa976562ef4193781725349f504
[PASS] Docker image built successfully: forgetasks-api:g03-local-ci-1792855551
[PASS] Container user is non-root UID 10001
[PASS] No sensitive keywords in image labels
[WARN] Trivy scan skipped (--skip-trivy)
[WARN] Gitleaks not installed — skipping local scan.
[WARN] Install: https://github.com/gitleaks/gitleaks
[WARN] The GitHub Actions CI pipeline enforces this check on push.
[WARN] actionlint not installed — skipping workflow lint.
[WARN] Install: https://github.com/rhysd/actionlint#installation

============================================================
 G03 Local CI Verification Summary
   PASS: 7   FAIL: 0   WARN: 6
============================================================
[PASS] Local CI verification complete.
Exit code: 0
```

> Note: WARN items (Trivy, Gitleaks, actionlint) are not installed locally but are enforced
> in the GitHub Actions CI runner (ubuntu-latest). All WARN items link to official installation
> guides in the script output.

---

## 5. G01 Regression Verification

```
./mvnw clean verify (from verify_g03_local.sh)
Tests run: 43, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
JaCoCo instruction coverage: 94.09%  (gate: ≥80%) — PASS
JaCoCo branch coverage:      91.23%  (gate: ≥80%) — PASS
```

---

## 6. Workflow Files Validated

| File | Size | YAML structure | Trust |
|---|---|---|---|
| `.github/workflows/ci.yml` | 9.6 KB | Valid | Untrusted CI (read-only) |
| `.github/workflows/publish.yml` | 7.6 KB | Valid | Trusted CD (packages:write, dispatch only) |
| `.github/dependabot.yml` | 1.7 KB | Valid | Supply-chain update automation |

---

## 7. Risk Register Updates

| Risk ID | Description | Mitigation | Status |
|---|---|---|---|
| R-G03-01 | Docker Hub rate limits on GitHub Actions runner | Maven cache + BuildKit GHA cache reduces pulls | MITIGATED |
| R-G03-02 | GHCR token leakage via workflow logs | GITHUB_TOKEN is short-lived; never echoed to logs | MITIGATED |
| R-G03-03 | Supply chain attack via unpinned actions | Dependabot monitors action versions weekly; no `@latest` | MITIGATED |
| R-G03-04 | Accidental image publication | `workflow_dispatch` only + "PUBLISH" confirmation guard + Trivy pre-push gate | MITIGATED |
| R-G03-05 | Floating `latest` tag immutability | Images tagged by git SHA; floating tags are secondary | MITIGATED |
| R-G03-06 | CRITICAL CVEs in base image | Trivy `--ignore-unfixed` gate at CRITICAL severity in both CI and publish workflows | MITIGATED |

---

## 8. GitHub Repository Setup Instructions

To activate CI and CD, push the current working tree to GitHub and configure:

### 8.1 Push to GitHub

```bash
# From WSL Ubuntu
cd /mnt/c/Project/ForgeOps
git push origin master
```

### 8.2 Branch Protection (Required)

Settings → Branches → Add rule for `master`:
- [x] Require status checks to pass before merging
  - Required check: **CI Gate**
- [x] Require branches to be up to date before merging
- [x] Restrict who can push to matching branches (optional: owner only)
- [x] Do not allow bypassing the above settings

### 8.3 Enable GitHub Code Scanning

GitHub Code Scanning receives Trivy SARIF results automatically on the first CI run. No
additional configuration is required beyond the workflow file permissions.

### 8.4 Trigger a Controlled Publish to GHCR

Actions → "Publish to GHCR" → Run workflow:
- **git_sha**: `<full commit SHA to release>`
- **semver_tag**: `1.0.1` (or leave blank for SHA-only tagging; do NOT reuse `1.0.0`)
- **confirm**: `PUBLISH`

Pull the published image by its immutable digest:
```bash
docker pull ghcr.io/<owner>/forgetasks-api@sha256:<digest>
```

### 8.5 Post-Release Incident Record (Run 40121874920) & Remediation

On October 24, 2026, the first controlled publication was executed against master commit `995a92954000f987736875be6881912a74b8b07e` (GitHub Actions Run `40121874920`).

**Observed Incident:**
1. All preflight validations (commit format, master HEAD, passing CI Gate) succeeded.
2. The manual `release` environment approval succeeded.
3. Docker successfully built the candidate image once, verified the candidate ID, passed Trivy CRITICAL and HIGH gates (0 vulnerabilities at configured threshold), and pushed all three tags:
   - `ghcr.io/tm-threemavithana/forgetasks-api:sha-995a929`
   - `ghcr.io/tm-threemavithana/forgetasks-api:<commit-sha>`
   - `ghcr.io/tm-threemavithana/forgetasks-api:1.0.0`
4. Published registry manifest digest confirmed by GHCR:
   `sha256:3d297bba979079d38ee0f91b87c07648676e2f4adb26955c90e029f3dcfbcaba`
5. The workflow then aborted at step `Record and verify published image digest`:
   `Error: Could not determine published repository digest from Docker daemon.`
6. Downstream consequence: The workflow terminated before step 13 (`Attest build provenance`), leaving the published `1.0.0` image without an attestation record.

**Root Causes:**
1. *Case Mismatch in Pattern Matching:* `REGISTRY_IMAGE` in the workflow contained `ghcr.io/TM-threemavithana/forgetasks-api` (preserving GitHub repository casing), but GHCR and `docker/metadata-action` automatically lowercase registry image references (`ghcr.io/tm-threemavithana/forgetasks-api`). The pattern `grep "^${REGISTRY_IMAGE}@"` failed to match in `.RepoDigests`.
2. *Fragile Local Daemon Reliance:* Relying on local daemon `.RepoDigests` rather than querying the registry directly is brittle and prone to caching/formatting discrepancies.

**Remediation Applied on branch `g03-registry-digest-fix`:**
1. Canonical lowercase image normalization in `validate-release` (`canonical_image` output).
2. Authoritative registry manifest digest lookup via `docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$tag"` across every published tag.
3. Multi-tag consistency validation ensuring all tags resolve to the identical 64-char sha256 digest.
4. Remote manifest configuration digest comparison to pre-push scanned candidate image ID.
5. Mandatory SLSA build provenance attestation: removed `continue-on-error: true`.
6. Expanded automated regression test suite to 70 checks in `scripts/test_publish_hardening.py` with 100% pass rate.

**Registry Immutability & Next Release Procedure:**
Tag `1.0.0` is already published in GHCR and must NOT be overwritten. The next controlled publication after this fix is merged to master must use version `1.0.1` (or SHA-only tags).

### 8.6 Verified Production Release (v1.0.1) & Cryptographic Attestation Evidence

Following the merge of PR #13 on commit `7adeec6fddda8c2e15f2f390e99f56c5b35d2fe2`:

1. **Master CI Run (`40127142460`):**
   - Verified commit: `7adeec6fddda8c2e15f2f390e99f56c5b35d2fe2`
   - URL: `https://github.com/TM-threemavithana/ForgeOps/actions/runs/40127142460`
   - Maven verify (43 tests, JaCoCo instruction 94.09%, branch 91.23%): PASSED.
   - Docker non-root check (UID 10001): PASSED.
   - Gitleaks full-history scan (`fetch-depth: 0`): PASSED (0 secrets detected).
   - Trivy vulnerability scan: PASSED (0 CRITICAL unfixed CVEs at configured threshold).
   - `ci-gate` aggregate status: SUCCESS.

2. **GHCR Release Run (`40127622068`):**
   - URL: `https://github.com/TM-threemavithana/ForgeOps/actions/runs/40127622068`
   - Target version: `1.0.1`
   - Protected environment: `release` (manual deployment approval completed).
   - Pre-push Trivy gate: PASSED (0 CRITICAL or HIGH unfixed CVEs at configured threshold).
   - Published tags: `1.0.1`, `sha-7adeec6`, and commit tag.
   - Authoritative manifest digest verified from GHCR across all tags:
     `sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691`
   - Remote manifest config digest verified against scanned candidate image ID.

3. **CycloneDX 1.6 SBOM Validation:**
   - Artifact: `forgetasks-api-sbom.cdx.json`
   - Local evidence: `/home/tharuka/forgeops-g03-verification/forgetasks-api-sbom.cdx.json`
   - Specification: CycloneDX v1.6
   - Inventory: 124 components, 125 dependency entries.
   - Note: The SBOM provides an auditable component inventory for ongoing dependency tracking; having zero vulnerability entries in the SBOM does not equate to vulnerability scanning, which is independently evaluated by Trivy.

4. **Cryptographic Build Provenance Verification:**
   - Generated via `actions/attest-build-provenance@v2` signed by GitHub Actions OIDC.
   - Verified using GitHub CLI:
     ```bash
     gh attestation verify oci://ghcr.io/tm-threemavithana/forgetasks-api@sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691 --owner TM-threemavithana
     ```
   - Exit code: `0` (Success, 1 matching signed attestation).
   - Local evidence: `/home/tharuka/forgeops-g03-verification/provenance-verification.json`
   - Predicate type: `https://slsa.dev/provenance/v1`
   - Subject: `ghcr.io/tm-threemavithana/forgetasks-api` @ `sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691`
   - Note: Proves non-forgeable build origin from the repository workflow via GitHub Actions OIDC; does not constitute external commercial SLSA certification.

5. **Nonblocking Maintenance Observations:**
   - Local scan tools (Trivy, Gitleaks, actionlint) are optional on local workstation and authoritatively enforced in GitHub Actions runner.
   - Trivy `ignore-unfixed: true` threshold policy avoids blocking on unpatchable upstream OS packages.
   - Initial `1.0.0` image remains in GHCR without attestation under immutability policy; superseded by fully attested release `1.0.1`.

---

## 9. Gate Result

| Acceptance Test | Result | Evidence |
|---|---|---|
| A-301: CI workflow syntax and trust model | PASS | File inspection, local verification; verified in CI run 40127142460 |
| A-302: Publish workflow safety controls | PASS | 70 automated regression tests in `test_publish_hardening.py`; verified in release run 40127622068 |
| A-303: Local CI counterpart (`make ci-local`) | PASS | `verify_g03_local.sh` output |
| Maven verify (43 tests, JaCoCo ≥80%) | PASS | Local run included in A-303; passed in CI run 40127142460 |
| Docker non-root validation | PASS | Local run included in A-303; UID 10001 verified in CI run 40127142460 |
| No secrets in workflow files | PASS | No PATs; GITHUB_TOKEN only; Gitleaks scan passed in CI |
| Dependabot supply-chain coverage | PASS | `.github/dependabot.yml` |
| G01 regression | PASS | 43/43 tests, BUILD SUCCESS |
| Production Release Verification | PASS | Run `40127622068` published `1.0.1` to GHCR (`sha256:629436fe1cc2d585ac3bae2e62db2b09fd19ed00fb7b1d83bd891e5d3346b691`); authoritative digest and signed SLSA provenance verified |

**G03 Status: PASSED — VERIFIED**

Gate G03 has met all acceptance criteria across local and GitHub Actions environments. The software supply chain is secured, release 1.0.1 is published and cryptographically attested, and the pipeline is verified for GitOps promotion in Gate G04.
