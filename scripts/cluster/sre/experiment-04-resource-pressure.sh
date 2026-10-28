#!/usr/bin/env bash
# ForgeOps Gate G12 - Resilience Experiment 04: Bounded Resource Pressure & Saturation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${SCRIPT_DIR}/common-sre.sh"

TARGET_NS="${1:-$DISPOSABLE_NAMESPACE}"
SERVICE_NAME="sre-api"
MODE="${2:-execute}"

echo "======================================================================="
echo "ForgeOps G12 Resilience Experiment 04: Bounded Resource Pressure"
echo "Target Namespace:      $TARGET_NS"
echo "Target Service:        $SERVICE_NAME"
echo "Concurrency Profile:   Progressive ramp (5 to max 25 VUs, bounded)"
echo "Safety Thresholds:     Abort if error rate > 5% or p95 > 1000ms"
echo "Expected Impact:       Increased CPU/RAM within limits; 0 restarts; 0 OOMKills"
echo "Rollback / Mitigation: Automatic k6 test termination on threshold breach"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_pass "Preflight validation and parameter check completed successfully (dry-run)."
  exit 0
fi

# Step 2: Check target endpoint
log_info "Verifying service port-forward or cluster connectivity..."
PORT=8082
log_info "Setting up temporary local port-forward to $SERVICE_NAME:8080 on port $PORT..."
kubectl port-forward -n "$TARGET_NS" "svc/$SERVICE_NAME" "${PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
trap "kill -9 $PF_PID >/dev/null 2>&1 || true" EXIT INT TERM ERR

sleep 2

# Verify target is reachable
if ! curl -sf "http://127.0.0.1:${PORT}/actuator/health" >/dev/null; then
  log_err "Failed to reach $SERVICE_NAME via port-forward on port $PORT"
  exit 1
fi
log_pass "Endpoint reachable at http://127.0.0.1:${PORT}/actuator/health"

# Step 3: Record baseline pod restart count
BASELINE_RESTARTS="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | tr ' ' '+' | bc || echo 0)"
log_info "Baseline restart count across pods: $BASELINE_RESTARTS"

# Step 4: Execute bounded k6 stress test
log_info "Executing bounded k6 stress test against http://127.0.0.1:${PORT}..."
T_START="$(date +%s%N)"

TARGET_URL="http://127.0.0.1:${PORT}" k6 run --quiet "${REPO_ROOT}/tests/load/k6/stress.js"

T_END="$(date +%s%N)"
DURATION_S=$(( (T_END - T_START) / 1000000000 ))
log_pass "Bounded stress test completed in ${DURATION_S}s."

# Step 5: Post-stress inspection
FINAL_RESTARTS="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | tr ' ' '+' | bc || echo 0)"
log_info "Final restart count: $FINAL_RESTARTS (baseline: $BASELINE_RESTARTS)"

if [[ "$FINAL_RESTARTS" -gt "$BASELINE_RESTARTS" ]]; then
  log_err "Pod restarted during stress test! Possible OOMKill or probe failure."
  exit 1
fi

# Check for OOMKilled containers
OOM_COUNT="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}' | grep -c "OOMKilled" || true)"
if [[ "$OOM_COUNT" -gt 0 ]]; then
  log_err "Detected OOMKilled container during resource pressure test!"
  exit 1
fi

assert_protected_pvcs_intact

log_pass "Resilience Experiment 04 PASSED! (0 OOMKills, 0 unexpected restarts, Protected PVCs: Intact)"
