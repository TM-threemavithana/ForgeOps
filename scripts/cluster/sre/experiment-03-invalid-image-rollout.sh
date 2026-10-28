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

# Step 2: Record baseline image and Deployment UID
log_info "Recording steady-state deployment status in $TARGET_NS..."
INITIAL_IMAGE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].image}')"
INITIAL_DEP_UID="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.metadata.uid}')"
BASELINE_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"

log_info "Initial healthy image: $INITIAL_IMAGE"
log_info "Deployment UID: $INITIAL_DEP_UID (Ready replicas: $BASELINE_READY)"

# Explicit G08 Rehearsal baseline check
G08_IMAGE="$(kubectl get deployment forgetasks-rehearsal-api -n forgeops-gitops-rehearsal -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
G08_DEP_UID="$(kubectl get deployment forgetasks-rehearsal-api -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"

RESTORED=0
cleanup() {
  local exit_code=$?
  if [[ "$RESTORED" -ne 1 && -n "${INITIAL_IMAGE:-}" ]]; then
    log_warn "Executing emergency cleanup: Restoring deployment to initial healthy image: $INITIAL_IMAGE..."
    kubectl set image deployment/"$DEPLOYMENT_NAME" "api=$INITIAL_IMAGE" -n "$TARGET_NS" >/dev/null 2>&1 || kubectl rollout undo deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" >/dev/null 2>&1 || true
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$TARGET_NS" --timeout=90s >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM ERR

# Step 3: Trigger invalid image rollout strictly in TARGET_NS
log_warn "Injecting fault: Updating deployment image to non-existent tag..."
T_START="$(date +%s%N)"
kubectl set image deployment/"$DEPLOYMENT_NAME" "api=$INVALID_IMAGE" -n "$TARGET_NS"

# Step 4: Detect rollout stall and ImagePullBackOff
log_info "Monitoring for ImagePullBackOff or ErrImagePull..."
T_DETECT=""
for i in {1..35}; do
  FAIL_STATUS="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=sre-api -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' || true)"
  if [[ "$FAIL_STATUS" =~ (ImagePullBackOff|ErrImagePull) ]]; then
    T_DETECT="$(date +%s%N)"
    log_info "Detected container waiting reason: $FAIL_STATUS"
    break
  fi
  sleep 1
done

if [[ -z "$T_DETECT" ]]; then
  log_warn "Pod not yet in ImagePullBackOff within 35s; inspecting pod events..."
  kubectl get events -n "$TARGET_NS" --sort-by='.metadata.creationTimestamp' | tail -n 5 || true
fi

# Confirm existing pods are still serving traffic
STILL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"
log_info "Ready replicas during stalled rollout: $STILL_READY (Zero downtime preserved by maxUnavailable=0)"

if [[ "$STILL_READY" -lt 1 ]]; then
  log_err "CRITICAL: Service degraded during invalid rollout! Expected existing replicas to remain ready."
  exit 1
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
FINAL_DEP_UID="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.metadata.uid}')"
FINAL_READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$TARGET_NS" -o jsonpath='{.status.readyReplicas}')"

if [[ "$FINAL_IMAGE" != "$INITIAL_IMAGE" || "$FINAL_READY" -ne "$BASELINE_READY" ]]; then
  log_err "Rollback verification failed! Image: $FINAL_IMAGE, Ready: $FINAL_READY"
  exit 1
fi
if [[ "$FINAL_DEP_UID" != "$INITIAL_DEP_UID" ]]; then
  log_err "Deployment UID shifted during rollout undo! Expected $INITIAL_DEP_UID, got $FINAL_DEP_UID"
  exit 1
fi

# Step 7: Verify G08 rehearsal was completely unaffected
FINAL_G08_IMAGE="$(kubectl get deployment forgetasks-rehearsal-api -n forgeops-gitops-rehearsal -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
FINAL_G08_DEP_UID="$(kubectl get deployment forgetasks-rehearsal-api -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"

if [[ "$FINAL_G08_IMAGE" != "$G08_IMAGE" || "$FINAL_G08_DEP_UID" != "$G08_DEP_UID" ]]; then
  log_err "CRITICAL SAFETY VIOLATION: G08 Rehearsal deployment was affected by experiment!"
  exit 1
fi
log_pass "Verified: G08 Rehearsal deployment remained completely unaffected (Image: $FINAL_G08_IMAGE, UID: $FINAL_G08_DEP_UID)."

RESTORED=1
assert_protected_pvcs_intact

log_pass "Resilience Experiment 03 PASSED! (TTR: ${TTR_MS}ms, Restored Image: $FINAL_IMAGE, Protected PVCs: Intact)"
