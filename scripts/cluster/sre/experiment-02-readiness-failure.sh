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

# Step 2: Record baseline configuration and healthy endpoints
log_info "Verifying steady state for $DEPLOYMENT_NAME in $TARGET_NS..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=60s

ORIGINAL_PROBE_PATH="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')"
if [[ -z "$ORIGINAL_PROBE_PATH" ]]; then
  ORIGINAL_PROBE_PATH="/actuator/health/readiness"
fi
log_info "Recorded original readiness probe path: $ORIGINAL_PROBE_PATH"

BASELINE_ENDPOINTS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)"
log_info "Baseline healthy endpoint IPs: $BASELINE_ENDPOINTS"

if [[ "$BASELINE_ENDPOINTS" -lt 2 ]]; then
  log_err "Expected at least 2 active endpoints, found $BASELINE_ENDPOINTS"
  exit 1
fi

RESTORED=0
cleanup() {
  local exit_code=$?
  if [[ "$RESTORED" -ne 1 && -n "${ORIGINAL_PROBE_PATH:-}" ]]; then
    log_warn "Executing emergency cleanup: Restoring original readiness probe path in $TARGET_NS..."
    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p="[
      {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/readinessProbe/httpGet/path\", \"value\": \"${ORIGINAL_PROBE_PATH}\"}
    ]" >/dev/null 2>&1 || true
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=90s >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM ERR

# Step 3: Inject readiness failure via patch
log_warn "Injecting fault: Updating readiness probe path to non-existent endpoint..."
T_START="$(date +%s%N)"

kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/actuator/health/simulated-readiness-failure"}
]'

# Step 4: Verify traffic exclusion on unready replica
log_info "Observing rolling surge pod readiness status and endpoint exclusion..."
T_DETECT=""
UNREADY_POD=""
UNREADY_POD_IP=""

for i in {1..50}; do
  UNREADY_POD="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}' | head -n 1 || true)"
  if [[ -n "$UNREADY_POD" ]]; then
    UNREADY_POD_IP="$(kubectl get pod "$UNREADY_POD" -n "$TARGET_NS" -o jsonpath='{.status.podIP}' || true)"
    if [[ -n "$UNREADY_POD_IP" ]]; then
      T_DETECT="$(date +%s%N)"
      log_info "Detected unready surge pod: $UNREADY_POD (IP: $UNREADY_POD_IP)"
      break
    fi
  fi
  sleep 1
done

if [[ -z "$T_DETECT" ]]; then
  log_err "Failed to detect unready surge pod within timeout!"
  exit 1
fi

TTD_MS=$(( (T_DETECT - T_START) / 1000000 ))
log_pass "Time To Detect (TTD): ${TTD_MS} ms"

# Verify that the unready pod is EXCLUDED from ready service endpoints
READY_IPS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[*].addresses[*].ip}')"
log_info "Active ready endpoint IPs during fault: $READY_IPS"

if echo "$READY_IPS" | grep -qw "$UNREADY_POD_IP"; then
  log_err "TRAFFIC EXCLUSION FAILURE: Unready pod IP $UNREADY_POD_IP is still present in ready endpoints!"
  exit 1
fi
log_pass "Confirmed: Unready pod IP $UNREADY_POD_IP is strictly excluded from Service ready endpoints."

# Step 5: Rollback and restore healthy probe
log_info "Initiating rollback: restoring original readiness probe path: $ORIGINAL_PROBE_PATH..."
T_RECOVER_START="$(date +%s%N)"

kubectl patch deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/readinessProbe/httpGet/path\", \"value\": \"${ORIGINAL_PROBE_PATH}\"}
]"

# Step 6: Wait for full recovery
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s

T_RECOVER_END="$(date +%s%N)"
TTR_MS=$(( (T_RECOVER_END - T_RECOVER_START) / 1000000 ))
log_pass "Time To Recover (TTR): ${TTR_MS} ms"

FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
DESIRED_REPLICAS="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}')"

if [[ "$FINAL_READY" -ne "$DESIRED_REPLICAS" ]]; then
  log_err "Final ready replicas mismatch: $FINAL_READY/$DESIRED_REPLICAS"
  exit 1
fi

FINAL_ENDPOINTS="$(kubectl get endpoints "$SERVICE_NAME" -n "$TARGET_NS" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)"
log_info "Final healthy endpoint IPs: $FINAL_ENDPOINTS"

if [[ "$FINAL_ENDPOINTS" -lt 2 ]]; then
  log_err "Final endpoints count below threshold: $FINAL_ENDPOINTS"
  exit 1
fi

RESTORED=1
assert_protected_pvcs_intact

log_pass "Resilience Experiment 02 PASSED! (TTD: ${TTD_MS}ms, TTR: ${TTR_MS}ms, Exclusion Verified, Protected PVCs: Intact)"
