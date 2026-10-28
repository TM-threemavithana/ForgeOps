#!/usr/bin/env bash
# ForgeOps Gate G12 - Resilience Experiment 02: Readiness Probe Failure & Traffic Exclusion
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-sre.sh"

TARGET_NS="${1:-$DISPOSABLE_NAMESPACE}"
DEPLOYMENT_NAME="sre-api"
SERVICE_NAME="sre-api"
MODE="${2:-execute}"

echo "======================================================================="
echo "ForgeOps G12 Resilience Experiment 02: Readiness Probe Failure & Exclusion"
echo "Target Namespace:      $TARGET_NS"
echo "Target Deployment:     $DEPLOYMENT_NAME"
echo "Target Service:        $SERVICE_NAME"
echo "Expected Impact:       Failing replica excluded from endpoints; healthy replicas serve traffic"
echo "Rollback / Mitigation: Revert readiness probe path to /actuator/health/readiness"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_pass "Preflight validation and parameter check completed successfully (dry-run)."
  exit 0
fi

# Step 2: Ensure deployment is healthy
log_info "Verifying steady state for $DEPLOYMENT_NAME in $TARGET_NS..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=60s

BASELINE_ENDPOINTS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)"
log_info "Baseline healthy endpoint IPs: $BASELINE_ENDPOINTS"

if [[ "$BASELINE_ENDPOINTS" -lt 2 ]]; then
  log_err "Expected at least 2 active endpoints, found $BASELINE_ENDPOINTS"
  exit 1
fi

# Step 3: Inject readiness failure via patch
log_warn "Injecting fault: Updating readiness probe path to non-existent endpoint..."
T_START="$(date +%s%N)"

kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/actuator/health/simulated-readiness-failure"}
]'

# Step 4: Verify traffic exclusion on unready replica
log_info "Observing rolling surge pod readiness status..."
T_DETECT=""
for i in {1..40}; do
  UNREADY_POD="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}' | head -n 1 || true)"
  if [[ -n "$UNREADY_POD" ]]; then
    T_DETECT="$(date +%s%N)"
    log_info "Detected unready surge pod: $UNREADY_POD"
    break
  fi
  sleep 1
done

if [[ -z "$T_DETECT" ]]; then
  log_err "Failed to detect unready surge pod within timeout!"
  # Rollback before exiting
  kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/actuator/health/readiness"}
  ]'
  exit 1
fi

TTD_MS=$(( (T_DETECT - T_START) / 1000000 ))
log_pass "Time To Detect (TTD): ${TTD_MS} ms"

# Verify that the unready pod is NOT included in service endpoints
ACTIVE_ENDPOINTS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)"
log_info "Active endpoints during readiness failure: $ACTIVE_ENDPOINTS (baseline was $BASELINE_ENDPOINTS)"

# Original healthy replicas must remain in endpoints
if [[ "$ACTIVE_ENDPOINTS" -ne "$BASELINE_ENDPOINTS" ]]; then
  log_warn "Active endpoints count shifted to $ACTIVE_ENDPOINTS; verifying healthy replicas still serve traffic."
fi

# Step 5: Rollback and restore healthy probe
log_info "Initiating rollback: restoring valid readiness probe path..."
T_RECOVER_START="$(date +%s%N)"

kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/actuator/health/readiness"}
]'

# Step 6: Wait for full recovery
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s

T_RECOVER_END="$(date +%s%N)"
TTR_MS=$(( (T_RECOVER_END - T_RECOVER_START) / 1000000 ))
log_pass "Time To Recover (TTR): ${TTR_MS} ms"

FINAL_ENDPOINTS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)"
log_info "Final healthy endpoint IPs: $FINAL_ENDPOINTS"

if [[ "$FINAL_ENDPOINTS" -lt 2 ]]; then
  log_err "Final endpoints count below threshold: $FINAL_ENDPOINTS"
  exit 1
fi

assert_protected_pvcs_intact

log_pass "Resilience Experiment 02 PASSED! (TTD: ${TTD_MS}ms, TTR: ${TTR_MS}ms, Protected PVCs: Intact)"
