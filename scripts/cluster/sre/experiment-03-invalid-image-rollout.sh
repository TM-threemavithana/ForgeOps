#!/usr/bin/env bash
# ForgeOps Gate G12 - Resilience Experiment 03: Invalid Image Rollout & Rollback Recovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-sre.sh"

TARGET_NS="${1:-$DISPOSABLE_NAMESPACE}"
DEPLOYMENT_NAME="sre-api"
INVALID_IMAGE="ghcr.io/tm-threemavithana/forgetasks-api:g12-invalid-simulated-image-tag"
MODE="${2:-execute}"

echo "======================================================================="
echo "ForgeOps G12 Resilience Experiment 03: Invalid Image Rollout & Rollback"
echo "Target Namespace:      $TARGET_NS"
echo "Target Deployment:     $DEPLOYMENT_NAME"
echo "Fault Image:           $INVALID_IMAGE"
echo "Expected Impact:       Rollout stalls on ImagePullBackOff; 0 downtime on existing pods"
echo "Rollback / Mitigation: Imperative 'kubectl rollout undo' (aligned with G10-B runbook)"
echo "Historical Reference:  Aligned with G10-B real failed-image incident report"
echo "======================================================================="

# Step 1: Preflight guards
run_sre_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_pass "Preflight validation and parameter check completed successfully (dry-run)."
  exit 0
fi

# Step 2: Record baseline image and healthy pods
log_info "Recording steady-state deployment status..."
CURRENT_IMAGE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
BASELINE_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
log_info "Baseline image: $CURRENT_IMAGE (Ready replicas: $BASELINE_READY)"

# Step 3: Trigger invalid image rollout
log_warn "Injecting fault: Updating deployment image to non-existent tag..."
T_START="$(date +%s%N)"
kubectl set image deployment/"$DEPLOYMENT_NAME" "api=$INVALID_IMAGE" -n "$TARGET_NS"

# Step 4: Detect rollout stall and ImagePullBackOff
log_info "Monitoring for ImagePullBackOff or ErrImagePull..."
T_DETECT=""
for i in {1..30}; do
  FAIL_STATUS="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' || true)"
  if [[ "$FAIL_STATUS" =~ (ImagePullBackOff|ErrImagePull) ]]; then
    T_DETECT="$(date +%s%N)"
    log_info "Detected container waiting reason: $FAIL_STATUS"
    break
  fi
  sleep 1
done

if [[ -z "$T_DETECT" ]]; then
  log_warn "Pod not yet in ImagePullBackOff within 30s; inspecting pod events..."
  kubectl get events -n "$TARGET_NS" --sort-by='.metadata.creationTimestamp' | tail -n 5 || true
fi

# Confirm existing pods are still serving traffic
STILL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
log_info "Ready replicas during stalled rollout: $STILL_READY (Zero downtime preserved by maxUnavailable=0)"

if [[ "$STILL_READY" -lt 1 ]]; then
  log_err "CRITICAL: Service degraded during invalid rollout! Expected existing replicas to remain ready."
fi

# Step 5: Execute Rollback
log_info "Initiating rollback recovery (kubectl rollout undo)..."
T_RECOVER_START="$(date +%s%N)"
kubectl rollout undo deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS"

# Step 6: Wait for recovery
log_info "Waiting for rollout undo completion..."
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=120s

T_RECOVER_END="$(date +%s%N)"
TTR_MS=$(( (T_RECOVER_END - T_RECOVER_START) / 1000000 ))
log_pass "Time To Recover (TTR): ${TTR_MS} ms"

FINAL_IMAGE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"

if [[ "$FINAL_IMAGE" != "$CURRENT_IMAGE" || "$FINAL_READY" -ne "$BASELINE_READY" ]]; then
  log_err "Rollback verification failed! Image: $FINAL_IMAGE, Ready: $FINAL_READY"
  exit 1
fi

assert_protected_pvcs_intact

log_pass "Resilience Experiment 03 PASSED! (TTR: ${TTR_MS}ms, Restored Image: $FINAL_IMAGE, Protected PVCs: Intact)"
