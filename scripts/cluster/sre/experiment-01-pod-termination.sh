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
echo "Expected Impact:       1 pod gracefully terminated; surviving replica serves traffic; replacement scheduled"
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

# Step 3: Record initial pod inventory and UIDs
INITIAL_UIDS="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[*].metadata.uid}')"
VICTIM_POD="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[0].metadata.name}')"
VICTIM_UID="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[0].metadata.uid}')"
SURVIVOR_POD="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[1].metadata.name}')"
SURVIVOR_UID="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{.items[1].metadata.uid}')"

log_info "Selected victim pod: $VICTIM_POD (UID: $VICTIM_UID)"
log_info "Surviving healthy pod: $SURVIVOR_POD (UID: $SURVIVOR_UID)"

# Step 4: Record baseline and inject normal failure
T_START="$(date +%s%N)"
log_warn "Injecting fault: Deleting pod $VICTIM_POD normally (allowing standard termination lifecycle)..."
kubectl delete pod "$VICTIM_POD" -n "$TARGET_NS"

# Step 5: Measure Time To Detect (TTD) - Identify genuinely new replacement Pod by UID
log_info "Monitoring for replacement pod with novel UID (distinct from survivor $SURVIVOR_POD)..."
T_DETECT=""
REPLACEMENT_POD=""
REPLACEMENT_UID=""

for i in {1..60}; do
  ALL_CURRENT="$(kubectl get pods -n "$TARGET_NS" -l "$SELECTOR" -o jsonpath='{range .items[*]}{.metadata.name}{","}{.metadata.uid}{" "}{end}' 2>/dev/null || true)"
  for item in $ALL_CURRENT; do
    P_NAME="${item%%,*}"
    P_UID="${item##*,}"
    if ! echo "$INITIAL_UIDS" | grep -qw "$P_UID"; then
      REPLACEMENT_POD="$P_NAME"
      REPLACEMENT_UID="$P_UID"
      T_DETECT="$(date +%s%N)"
      log_info "Genuinely new replacement pod detected: $REPLACEMENT_POD (UID: $REPLACEMENT_UID)"
      break 2
    fi
  done
  sleep 0.5
done

if [[ -z "$T_DETECT" ]]; then
  log_err "Timeout waiting for Deployment controller to schedule replacement pod with distinct UID!"
  exit 1
fi

TTD_MS=$(( (T_DETECT - T_START) / 1000000 ))
log_pass "Time To Detect (TTD): ${TTD_MS} ms"

# Step 6: Measure Time To Recover (TTR) - All replicas achieve Ready status
log_info "Waiting for replacement pod $REPLACEMENT_POD and deployment to achieve full Ready state..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=90s

T_RECOVER="$(date +%s%N)"
TTR_MS=$(( (T_RECOVER - T_START) / 1000000 ))
log_pass "Time To Recover (TTR): ${TTR_MS} ms"

# Step 7: Post-experiment verification
FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
if [[ "$FINAL_READY" -ne "$DESIRED" ]]; then
  log_err "Final ready replicas mismatch: $FINAL_READY vs declared $DESIRED"
  exit 1
fi

# Verify replacement pod is running and ready
REPL_READY="$(kubectl get pod "$REPLACEMENT_POD" -n "$TARGET_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
if [[ "$REPL_READY" != "True" ]]; then
  log_err "Replacement pod $REPLACEMENT_POD is not in Ready state (status: $REPL_READY)!"
  exit 1
fi

assert_protected_pvcs_intact

log_pass "Resilience Experiment 01 PASSED! (TTD: ${TTD_MS}ms, TTR: ${TTR_MS}ms, New Pod UID: $REPLACEMENT_UID, Protected PVCs: Intact)"
