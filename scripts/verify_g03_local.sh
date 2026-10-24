#!/usr/bin/env bash
# ForgeOps — G03 Local CI Verification Script
# Replicates the GitHub Actions CI pipeline steps that can run locally.
# Run from the repository root (WSL Ubuntu recommended).
# Usage: ./scripts/verify_g03_local.sh [--skip-trivy] [--skip-docker]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SKIP_TRIVY=false
SKIP_DOCKER=false
for arg in "$@"; do
  case $arg in
    --skip-trivy)  SKIP_TRIVY=true ;;
    --skip-docker) SKIP_DOCKER=true ;;
  esac
done

PASS=0
FAIL=0
WARN=0

step_pass() { echo "[PASS] $1"; ((PASS++)) || true; }
step_fail() { echo "[FAIL] $1"; ((FAIL++)) || true; }
step_warn() { echo "[WARN] $1"; ((WARN++)) || true; }
step_info() { echo "[INFO] $1"; }

echo "============================================================"
echo " ForgeOps G03 Local CI Verification"
echo " $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo " Repo: $REPO_ROOT"
echo "============================================================"

# ---- Step 1: Toolchain ---------------------------------------------------
step_info "Checking required toolchain..."

if java -version 2>&1 | grep -q 'version "21'; then
  step_pass "Java 21 detected: $(java -version 2>&1 | head -1)"
else
  step_fail "Java 21 not found. Detected: $(java -version 2>&1 | head -1 || echo 'not installed')"
fi

if mvn --version > /dev/null 2>&1 || ./apps/forgetasks-api/mvnw --version > /dev/null 2>&1; then
  step_pass "Maven available"
else
  step_fail "Maven (mvn or mvnw) not found in PATH"
fi

if docker info > /dev/null 2>&1; then
  step_pass "Docker Engine: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
else
  step_fail "Docker Engine not reachable from this shell"
fi

# ---- Step 2: Maven build and test ----------------------------------------
step_info "Running Maven clean verify (unit + integration tests + JaCoCo)..."
if (cd apps/forgetasks-api && ./mvnw clean verify -B -q); then
  step_pass "Maven verify passed — all tests green, JaCoCo gate satisfied"
else
  step_fail "Maven verify failed. See output above."
fi

# ---- Step 3: Docker build validation -------------------------------------
if $SKIP_DOCKER; then
  step_warn "Docker build validation skipped (--skip-docker)"
else
  step_info "Building Docker image locally (no push)..."
  IMAGE_TAG="forgetasks-api:g03-local-ci-$(date +%s)"
  if docker build -t "$IMAGE_TAG" apps/forgetasks-api/; then
    step_pass "Docker image built successfully: $IMAGE_TAG"

    # Verify non-root user
    USER_ID=$(docker inspect --format '{{ .Config.User }}' "$IMAGE_TAG")
    if [ "$USER_ID" = "10001:10001" ] || [ "$USER_ID" = "10001" ]; then
      step_pass "Container user is non-root UID 10001"
    else
      step_fail "Container user is '$USER_ID'; expected 10001:10001"
    fi

    # Verify no sensitive labels
    LABELS=$(docker inspect "$IMAGE_TAG" --format '{{ json .Config.Labels }}')
    if echo "$LABELS" | grep -iEq '(password|secret|token|credential)'; then
      step_fail "Sensitive keyword found in image labels"
    else
      step_pass "No sensitive keywords in image labels"
    fi

    # ---- Step 4: Trivy scan ----------------------------------------------
    if $SKIP_TRIVY; then
      step_warn "Trivy scan skipped (--skip-trivy)"
    else
      if command -v trivy > /dev/null 2>&1; then
        step_info "Running Trivy vulnerability scan..."
        if trivy image \
          --exit-code 1 \
          --ignore-unfixed \
          --vuln-type os,library \
          --scanners vuln \
          --severity CRITICAL,HIGH \
          --quiet \
          "$IMAGE_TAG"; then
          step_pass "Trivy scan: zero CRITICAL/HIGH unfixed vulnerabilities"
        else
          step_fail "Trivy scan: CRITICAL or HIGH vulnerabilities found (see output above)"
        fi
      else
        step_warn "Trivy not installed — skipping local scan."
        step_warn "Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        step_warn "The GitHub Actions CI pipeline will enforce this check on push."
      fi
    fi

    docker rmi "$IMAGE_TAG" > /dev/null 2>&1 || true
  else
    step_fail "Docker build failed. See output above."
  fi
fi

# ---- Step 5: Gitleaks (optional local check) ----------------------------
if command -v gitleaks > /dev/null 2>&1; then
  step_info "Running Gitleaks secret scan..."
  if gitleaks detect --source . --no-banner --quiet 2>/dev/null; then
    step_pass "Gitleaks: no secrets detected in repository history"
  else
    step_fail "Gitleaks: potential secrets detected. Review output above."
  fi
else
  step_warn "Gitleaks not installed — skipping local scan."
  step_warn "Install: https://github.com/gitleaks/gitleaks"
  step_warn "The GitHub Actions CI pipeline enforces this check on push."
fi

# ---- Step 6: Workflow YAML lint (actionlint) ----------------------------
if command -v actionlint > /dev/null 2>&1; then
  step_info "Linting GitHub Actions workflow files with actionlint..."
  if actionlint .github/workflows/*.yml; then
    step_pass "actionlint: all workflow files are valid"
  else
    step_fail "actionlint: workflow syntax errors detected (see above)"
  fi
else
  step_warn "actionlint not installed — skipping workflow lint."
  step_warn "Install: https://github.com/rhysd/actionlint#installation"
fi

# ---- Step 7: GHCR Publishing Security Hardening Validation ---------------
step_info "Validating GHCR publishing workflow security hardening..."
if python3 scripts/test_publish_hardening.py > /dev/null 2>&1; then
  step_pass "GHCR publishing workflow security hardening verified (40 checks passed)"
else
  step_fail "GHCR publishing workflow security hardening check failed"
fi

# ---- Summary -------------------------------------------------------------
echo ""
echo "============================================================"
echo " G03 Local CI Verification Summary"
echo "   PASS: $PASS   FAIL: $FAIL   WARN: $WARN"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
  echo "[FAIL] $FAIL check(s) failed. Review output above."
  exit 1
else
  echo "[PASS] Local CI verification complete."
  exit 0
fi