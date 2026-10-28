#!/usr/bin/env bash
# ForgeOps Gate G12 - Hardened Teardown for Disposable SRE Lab Fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-sre.sh"

MODE="${1:-teardown}"

echo "======================================================================="
echo "ForgeOps G12: Disposable SRE Lab Teardown & Inventory Audit"
echo "Target Namespace: $DISPOSABLE_NAMESPACE"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$DISPOSABLE_NAMESPACE"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running teardown-sre-lab in validation mode (no deletion)..."
  log_pass "Teardown preflight validation passed."
  exit 0
fi

if ! kubectl get ns "$DISPOSABLE_NAMESPACE" >/dev/null 2>&1; then
  log_info "Namespace '$DISPOSABLE_NAMESPACE' does not exist; nothing to tear down."
  assert_protected_pvcs_intact
  exit 0
fi

# Step 2: Validate exact namespace identity and ownership labels
log_info "Auditing namespace metadata and ownership labels..."
NS_NAME="$(kubectl get ns "$DISPOSABLE_NAMESPACE" -o jsonpath='{.metadata.name}')"
if [[ "$NS_NAME" != "$DISPOSABLE_NAMESPACE" ]]; then
  log_err "CRITICAL REFUSAL: Target namespace name '$NS_NAME' does not match mandated '$DISPOSABLE_NAMESPACE'!"
  exit 1
fi

DISPOSABLE_LABEL="$(kubectl get ns "$DISPOSABLE_NAMESPACE" -o jsonpath='{.metadata.labels.forgeops\.dev/disposable}')"
ENV_LABEL="$(kubectl get ns "$DISPOSABLE_NAMESPACE" -o jsonpath='{.metadata.labels.forgeops\.dev/environment}')"

if [[ "$DISPOSABLE_LABEL" != "true" || "$ENV_LABEL" != "sre-lab" ]]; then
  log_err "CRITICAL REFUSAL: Namespace '$DISPOSABLE_NAMESPACE' is missing required disposable labels (disposable=$DISPOSABLE_LABEL, env=$ENV_LABEL)!"
  log_err "Preserving namespace and halting teardown to protect unverified resources."
  exit 1
fi

# Step 3: Complete resource inventory audit
log_info "Performing complete resource inventory audit in '$DISPOSABLE_NAMESPACE'..."

# A: Require zero PVCs
assert_no_pvc_in_disposable_ns

# B: Check for unexpected StatefulSets
STS_COUNT="$(kubectl get statefulsets -n "$DISPOSABLE_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$STS_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $STS_COUNT StatefulSet(s) in '$DISPOSABLE_NAMESPACE'! Halting teardown."
  exit 1
fi

# C: Check for unexpected Deployments (only sre-api and sre-db permitted)
DEP_LIST="$(kubectl get deployments -n "$DISPOSABLE_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for dep in $DEP_LIST; do
  if [[ "$dep" != "sre-api" && "$dep" != "sre-db" ]]; then
    log_err "UNEXPECTED DEPLOYMENT: Found unapproved deployment '$dep' in '$DISPOSABLE_NAMESPACE'! Preserving namespace and stopping."
    exit 1
  fi
done

# Step 4: Graceful, non-forced deletion without finalizer tampering
log_info "Deleting namespace '$DISPOSABLE_NAMESPACE' gracefully (standard deletion, no --force, no finalizer tampering)..."
kubectl delete namespace "$DISPOSABLE_NAMESPACE" --timeout=120s

# Step 5: Confirm deletion completed
if kubectl get ns "$DISPOSABLE_NAMESPACE" >/dev/null 2>&1; then
  log_warn "Namespace is still terminating; waiting up to 30s for finalization..."
  kubectl wait --for=delete namespace/"$DISPOSABLE_NAMESPACE" --timeout=30s || {
    log_err "Namespace '$DISPOSABLE_NAMESPACE' failed to terminate within timeout! Preserving state for operator review."
    exit 1
  }
fi

# Step 6: Final verification of all 5 protected PVCs
assert_protected_pvcs_intact

log_pass "Disposable SRE lab teardown completed cleanly and safely. All protected resources verified intact."
