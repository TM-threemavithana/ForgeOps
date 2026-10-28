#!/usr/bin/env bash
# ForgeOps Gate G13 - Hardened Teardown for Disposable Disaster Recovery Lab
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-dr.sh"

TARGET_NS="${1:-$DISPOSABLE_DR_NAMESPACE}"
MODE="${2:-teardown}"

echo "======================================================================="
echo "ForgeOps G13: Disposable Disaster Recovery Lab Teardown & Audit"
echo "Target Namespace: $TARGET_NS"
echo "======================================================================="

# Step 1: Preflight guards
run_dr_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running teardown-dr-lab in validation mode (no deletion)..."
  log_pass "Teardown preflight validation passed."
  exit 0
fi

if ! kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
  log_info "Namespace '$TARGET_NS' does not exist; nothing to tear down."
  assert_protected_pvcs_intact
  exit 0
fi

# Step 2: Validate exact namespace identity and ownership labels
log_info "Auditing namespace metadata and ownership labels..."
NS_NAME="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.name}')"
if [[ "$NS_NAME" != "$DISPOSABLE_DR_NAMESPACE" ]]; then
  log_err "CRITICAL REFUSAL: Target namespace name '$NS_NAME' does not match mandated '$DISPOSABLE_DR_NAMESPACE'!"
  exit 1
fi

DISPOSABLE_LABEL="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/disposable}' 2>/dev/null || true)"
ENV_LABEL="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/environment}' 2>/dev/null || true)"

if [[ "$DISPOSABLE_LABEL" != "true" || "$ENV_LABEL" != "dr-lab" ]]; then
  log_err "CRITICAL REFUSAL: Namespace '$TARGET_NS' is missing required disposable labels (disposable=$DISPOSABLE_LABEL, env=$ENV_LABEL)!"
  log_err "Preserving namespace and halting teardown to protect unverified resources."
  exit 1
fi

# Step 3: Complete resource inventory audit
log_info "Performing complete resource inventory audit in '$TARGET_NS'..."

# A: Require zero PVCs
assert_no_pvc_in_disposable_ns "$TARGET_NS"

# B: Check for unexpected StatefulSets
STS_COUNT="$(kubectl get statefulsets -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$STS_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $STS_COUNT StatefulSet(s) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

# C: Check for unexpected Deployments (only dr-source-db, dr-target-db, and dr-api permitted)
DEP_LIST="$(kubectl get deployments -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for dep in $DEP_LIST; do
  if [[ "$dep" != "dr-source-db" && "$dep" != "dr-target-db" && "$dep" != "dr-api" ]]; then
    log_err "UNEXPECTED DEPLOYMENT: Found unapproved deployment '$dep' in '$TARGET_NS'! Preserving namespace and stopping."
    exit 1
  fi
done

# Step 4: Graceful deletion without --force or finalizer tampering
log_info "Deleting namespace '$TARGET_NS' gracefully (standard deletion, no --force, no finalizer tampering)..."
kubectl delete namespace "$TARGET_NS" --timeout=120s

# Step 5: Confirm deletion completed
if kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
  log_warn "Namespace is still terminating; waiting up to 30s for finalization..."
  kubectl wait --for=delete "namespace/${TARGET_NS}" --timeout=30s || {
    log_err "Namespace '$TARGET_NS' failed to terminate within timeout! Preserving state for operator review."
    exit 1
  }
fi

# Step 6: Final verification of all 5 protected PVCs
assert_protected_pvcs_intact

log_pass "Disposable DR lab teardown completed cleanly and safely. All protected resources verified intact."
