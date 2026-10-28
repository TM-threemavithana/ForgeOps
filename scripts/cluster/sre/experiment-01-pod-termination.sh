#!/usr/bin/env bash
# ForgeOps Gate G12 - Resilience Experiment 01: API Pod Termination & Recovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-sre.sh"

TARGET_NS="${1:-$DISPOSABLE_NAMESPACE}"
DEPLOYMENT_NAME="sre-api"
SELECTOR="app.kubernetes.io/name=sre-api"
MODE="${2:-execute}"

echo "======================================================================="
echo "ForgeOps G12 Resilience Experiment 01: Pod Termination & Recovery"
echo "Target Namespace:      $TARGET_NS"
echo "Target Deployment:     $DEPLOYMENT_NAME"
echo "Label Selector:        $SELECTOR"
echo "Expected Impact:       1 pod killed; 2nd replica continues serving; controller replaces pod"
echo "Rollback / Mitigation: Automatic Deployment controller self-healing"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_pass "Preflight validation and parameter check completed successfully (dry-run)."
  exit 0
fi

# Step 2: Ensure target deployment is healthy
log_info "Verifying steady-state health for $DEPLOYMENT_NAME in $TARGET_NS..."
DESIRED="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}')"
READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"

if [[ "$READY" -lt "$DESIRED" || "$READY" -lt 2 ]]; then
  log_err "Deployment $DEPLOYMENT_NAME has only $READY/$DESIRED ready replicas; requires at least 2 ready replicas for chaos test!"
  exit 1
fi

# Step 3: Identify victim pod
VICTIM_POD="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
VICTIM_UID="$(kubectl get pod "$VICTIM_POD" -n "$TARGET_NS" -o jsonpath='{.metadata.uid}')"
VICTIM_NODE="$(kubectl get pod "$VICTIM_POD" -n "$TARGET_NS" -o jsonpath='{.spec.nodeName}')"

log_info "Selected victim pod: $VICTIM_POD (UID: $VICTIM_UID, Node: $VICTIM_NODE)"

# Step 4: Record baseline and inject failure
T_START="$(date +%s%N)"
log_warn "Injecting fault: Deleting pod $VICTIM_POD abruptly..."
kubectl delete pod "$VICTIM_POD" -n "$TARGET_NS" --grace-period=0 --force >/dev/null 2>&1 || kubectl delete pod "$VICTIM_POD" -n "$TARGET_NS" --now

# Step 5: Measure Time To Detect (TTD) - Controller schedules replacement
T_DETECT=""
for i in {1..30}; do
  NEW_POD="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[?(@.metadata.name != "'"$VICTIM_POD"'")].metadata.name}' | tr ' ' '\n' | grep -v "$VICTIM_POD" | head -n 1 || true)"
  if [[ -n "$NEW_POD" ]]; then
    T_DETECT="$(date +%s%N)"
    log_info "Replacement pod detected: $NEW_POD"
    break
  fi
  sleep 0.5
done

if [[ -z "$T_DETECT" ]]; then
  log_err "Timeout waiting for Deployment controller to schedule replacement pod!"
  exit 1
fi

TTD_MS=$(( (T_DETECT - T_START) / 1000000 ))
log_pass "Time To Detect (TTD): ${TTD_MS} ms"

# Step 6: Measure Time To Recover (TTR) - All replicas Ready
log_info "Waiting for replacement pod to achieve Ready status..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=60s

T_RECOVER="$(date +%s%N)"
TTR_MS=$(( (T_RECOVER - T_START) / 1000000 ))
log_pass "Time To Recover (TTR): ${TTR_MS} ms"

# Step 7: Post-experiment verification
FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
if [[ "$FINAL_READY" -ne "$DESIRED" ]]; then
  log_err "Final ready replicas mismatch: $FINAL_READY vs $DESIRED"
  exit 1
fi

assert_protected_pvcs_intact

log_pass "Resilience Experiment 01 PASSED! (TTD: ${TTD_MS}ms, TTR: ${TTR_MS}ms, Protected PVCs: Intact)"
