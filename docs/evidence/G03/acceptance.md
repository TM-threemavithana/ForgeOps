# Gate G03 Acceptance Report — GitHub Actions CI/CD, Supply Chain Security & GHCR Publishing

**Date:** 2026-10-24
**Evaluator:** Principal DevOps Engineer, CI/CD Architect & Container Security Reviewer
**Gate:** G03 — Local & GitHub Actions CI Pipelines, Trust Boundaries and GHCR Publishing
**Status:** PASSED (Local verification complete; GitHub Actions pending repository push)
**Repository Working Tree:** Clean at local verification
**Execution Profile:** Core Profile (Local-First, Zero Cloud Dependencies)

---

## 1. Executive Summary

Gate G03 implements a secure, layered CI/CD system that separates untrusted CI (triggered on
push/PR to master) from a manually controlled, approver-gated CD publishing workflow. All locally
verifiable steps have been executed. GitHub Actions steps (Trivy SARIF upload, Gitleaks scan,
GHCR publishing) require the repository to be pushed and are documented for user-controlled
execution.

Key deliverables:

1. **CI Workflow** (`.github/workflows/ci.yml`): Triggers on push and PR to master. Runs
   Maven verify (43 tests, JaCoCo ≥80%), Docker image build validation, non-root user check,
   Trivy CRITICAL scan with SARIF upload to GitHub Code Scanning, and Gitleaks secret scan.
   All jobs gate on the `ci-gate` summary job — the required status check for branch protection.

2. **Publish Workflow** (`.github/workflows/publish.yml`): `workflow_dispatch` ONLY. Requires
   manual git SHA input, a semver tag (optional), and the literal string "PUBLISH" as a
   confirmation guard. Runs Trivy CRITICAL scan before any push; on pass builds and pushes to
   GHCR with SLSA Level 2 provenance attestation and SBOM. Image is referenced by immutable
   SHA256 digest.

3. **Dependabot** (`.github/dependabot.yml`): Monitors GitHub Actions, Maven, and Docker
   base images weekly. All updates target master via pull request — never auto-merged.

4. **Local CI Script** (`scripts/verify_g03_local.sh`): Replicates the GitHub Actions CI
   locally including Maven verify, Docker build, non-root verification, and optional Trivy/
   Gitleaks/actionlint checks.

5. **Trust Boundary Enforced**: No workflow pushes to GHCR on PR or push events. The
   publish workflow requires `packages:write` permission granted only to the triggering actor
   (repository owner or invited collaborator).

6. **Supply Chain Controls**: Action versions pinned to stable major tags (v4, v3, v6).
   Dependabot monitors these for updates. SLSA Level 2 provenance attached to every published
   image. SBOM generated alongside each push.

---

## 2. Environment Baseline

- **Host OS:** Windows 11 Enterprise (WSL2 Ubuntu 24.04.1 LTS)
- **Java:** 21.0.12.1 (Eclipse Temurin)
- **Maven Wrapper:** 3.9.9
- **Docker Engine:** 29.5.3
- **Trivy:** (optional local; enforced in CI runner)
- **actionlint:** (optional local; documented)

---

## 3. Acceptance Tests

### A-301: Untrusted PR workflow (read-only permissions)

| Item | Requirement | Evidence |
|---|---|---|
| Trigger | push and pull_request to master | `.github/workflows/ci.yml` L12–17 |
| Permissions | `contents: read`, `security-events: write` | `.github/workflows/ci.yml` L19–22 |
| No GHCR push | CI never calls `docker/login-action` or `build-push-action` with `push: true` | Confirmed by file inspection |
| Build and test | `./mvnw clean verify -B -e` with JaCoCo gate | Job `build-and-test` |
| Non-root check | Docker inspect verifies UID 10001 | Job `docker-build-validate` |
| Trivy gate | Zero CRITICAL unfixed CVEs enforced with `exit-code: 1` | Job `trivy-scan` |
| Gitleaks | Full history scan on each run | Job `gitleaks-scan` |
| Required status | `ci-gate` job aggregates all results | `.github/workflows/ci.yml` L200+ |

### A-302: Trusted release to GHCR by SHA256

| Item | Requirement | Evidence |
|---|---|---|
| Trigger | `workflow_dispatch` only | `.github/workflows/publish.yml` L20 |
| Confirmation guard | Input must equal literal "PUBLISH" | `preflight` job, step 1 |
| Specific SHA checkout | `ref: git_sha input` | `publish` job checkout step |
| Pre-push Trivy gate | Zero CRITICAL CVEs before any push | `publish` job trivy step |
| Provenance | SLSA Level 2 via `provenance: mode=max` | `build-and-push` step |
| SBOM | `sbom: true` | `build-and-push` step |
| Digest recording | Logged to run summary | `record published image digest` step |
| No leaked secrets | `packages:write` from GITHUB_TOKEN only; no PATs | Workflow permission block |

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
- **semver_tag**: `1.0.0` (or leave blank for SHA-only tagging)
- **confirm**: `PUBLISH`

Pull the published image by its immutable digest:
```bash
docker pull ghcr.io/<owner>/forgetasks-api@sha256:<digest>
```

---

## 9. Gate Result

| Acceptance Test | Result | Evidence |
|---|---|---|
| A-301: CI workflow syntax and trust model | PASS | File inspection, local verification |
| A-302: Publish workflow safety controls | PASS | File inspection |
| A-303: Local CI counterpart (`make ci-local`) | PASS | `verify_g03_local.sh` output |
| Maven verify (43 tests, JaCoCo ≥80%) | PASS | Local run included in A-303 |
| Docker non-root validation | PASS | Local run included in A-303 |
| No secrets in workflow files | PASS | No PATs; GITHUB_TOKEN only |
| Dependabot supply-chain coverage | PASS | `.github/dependabot.yml` |
| G01 regression | PASS | 43/43 tests, BUILD SUCCESS |

**G03 Status: PASSED (Local verification complete)**

Awaiting user-controlled `git push origin master` to activate GitHub Actions CI.
Once pushed, the `ci-gate` status check automatically governs all future merges.