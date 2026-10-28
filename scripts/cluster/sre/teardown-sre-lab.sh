#!/usr/bin/env bash
# ForgeOps Gate G12 - Teardown Disposable SRE Lab Fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-sre.sh"

MODE="${1:-teardown}"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running teardown-sre-lab in validation mode (no deletion)..."
  run_sre_preflight_guards "$DISPOSABLE_NAMESPACE"
  log_pass "Teardown preflight validation passed."
  exit 0
fi

log_info "Initiating teardown of disposable SRE lab fixture in '$DISPOSABLE_NAMESPACE'..."

# Step 1: Preflight checks
run_sre_preflight_guards "$DISPOSABLE_NAMESPACE"

# Step 2: Delete namespace
if kubectl get ns "$DISPOSABLE_NAMESPACE" >/dev/null 2>&1; then
  log_info "Deleting namespace '$DISPOSABLE_NAMESPACE'..."
  kubectl delete namespace "$DISPOSABLE_NAMESPACE" --timeout=120s || {
    log_warn "Standard deletion timed out or encountered warnings; waiting for resource finalization..."
  }
else
  log_info "Namespace '$DISPOSABLE_NAMESPACE' does not exist; nothing to tear down."
fi

# Step 3: Re-verify protected PVCs
assert_protected_pvcs_intact

log_pass "SRE lab fixture teardown completed cleanly. Protected state verified intact."
