#!/usr/bin/env bash
# ForgeOps Gate G12 - Resilience Experiment 05: Kubernetes Declarative Configuration Reconciliation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${SCRIPT_DIR}/common-sre.sh"

TARGET_NS="${1:-$DISPOSABLE_NAMESPACE}"
DEPLOYMENT_NAME="sre-api"
MODE="${2:-execute}"

echo "======================================================================="
echo "ForgeOps G12 Resilience Experiment 05: Declarative Reconciliation"
echo "Target Namespace:      $TARGET_NS"
echo "Target Deployment:     $DEPLOYMENT_NAME"
echo "Drift Simulation:      Imperative replica scale out to 3"
echo "Expected Impact:       Detected drift between Git manifest and cluster state"
echo "Reconciliation Action: Declarative convergence via 'kubectl apply -k platform/sre-lab'"
echo "Architectural Context: Validates Kubernetes declarative reconciliation against"
echo "                       imperative drift, demonstrating the same reconciliation"
echo "                       principle leveraged by GitOps engines (Argo CD)"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_pass "Preflight validation and parameter check completed successfully (dry-run)."
  exit 0
fi

# Step 2: Record declared Git state
log_info "Reading declarative desired replica count from platform/sre-lab/api-deployment.yaml..."
DECLARED_REPLICAS="$(grep -E '^\s*replicas:' "${REPO_ROOT}/platform/sre-lab/api-deployment.yaml" | head -n 1 | awk '{print $2}')"
log_info "Declarative desired replicas: $DECLARED_REPLICAS"

LIVE_REPLICAS="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}')"
if [[ "$LIVE_REPLICAS" -ne "$DECLARED_REPLICAS" ]]; then
  log_err "Live cluster state ($LIVE_REPLICAS) does not match declared Git state ($DECLARED_REPLICAS) before drill!"
  exit 1
fi

RESTORED=0
cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM ERR
  if [[ "$RESTORED" -ne 1 ]]; then
    log_warn "Executing emergency cleanup: Restoring declarative state via kubectl apply -k platform/sre-lab..."
    kubectl apply -k "${REPO_ROOT}/platform/sre-lab" >/dev/null 2>&1 || true
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM ERR

# Step 3: Inject configuration drift imperatively
DRIFTED_COUNT=3
log_warn "Simulating unapproved imperative drift: scaling $DEPLOYMENT_NAME to $DRIFTED_COUNT replicas..."
T_START="$(date +%s%N)"
kubectl scale deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --replicas="$DRIFTED_COUNT"

# Wait for drift to manifest
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s
CURRENT_LIVE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}')"
log_info "Cluster state now in drifted condition: $CURRENT_LIVE replicas (Git declared: $DECLARED_REPLICAS)"

if [[ "$CURRENT_LIVE" -ne "$DRIFTED_COUNT" ]]; then
  log_err "Failed to establish drift state!"
  exit 1
fi

# Step 4: Execute Declarative Reconciliation
log_info "Executing declarative reconciliation: applying Git source-of-truth manifests..."
T_RECONCILE_START="$(date +%s%N)"

kubectl apply -k "${REPO_ROOT}/platform/sre-lab"

# Step 5: Wait for reconciliation
log_info "Waiting for deployment to reconcile back to declared $DECLARED_REPLICAS replicas..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s

T_RECONCILE_END="$(date +%s%N)"
TTR_MS=$(( (T_RECONCILE_END - T_RECONCILE_START) / 1000000 ))
log_pass "Time To Reconcile (TTR): ${TTR_MS} ms"

RESTORED_REPLICAS="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}')"
FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"

if [[ "$RESTORED_REPLICAS" -ne "$DECLARED_REPLICAS" || "$FINAL_READY" -ne "$DECLARED_REPLICAS" ]]; then
  log_err "Reconciliation failed! Replicas: $RESTORED_REPLICAS/$FINAL_READY (expected: $DECLARED_REPLICAS)"
  exit 1
fi

RESTORED=1
assert_protected_pvcs_intact

log_pass "Resilience Experiment 05 PASSED! (Declarative State Restored: ${FINAL_READY}/${DECLARED_REPLICAS}, Protected PVCs: Intact)"
