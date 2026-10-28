#!/usr/bin/env bash
# ForgeOps Gate G12 - Setup Disposable SRE Lab Fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-sre.sh"

MODE="${1:-deploy}"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running setup-sre-lab in validation mode (no deployment)..."
  run_sre_preflight_guards "$DISPOSABLE_NAMESPACE"
  kubectl kustomize "${REPO_ROOT}/platform/sre-lab" >/dev/null
  log_pass "SRE lab manifests and preflight validation passed."
  exit 0
fi

log_info "Starting deployment of disposable SRE lab fixture in '$DISPOSABLE_NAMESPACE'..."

# Step 1: Preflight checks
run_sre_preflight_guards "$DISPOSABLE_NAMESPACE"

# Step 2: Apply manifests
log_info "Applying Kustomize manifests from platform/sre-lab..."
kubectl apply -k "${REPO_ROOT}/platform/sre-lab"

# Step 3: Wait for ephemeral database
log_info "Waiting for ephemeral database rollout (timeout: 90s)..."
kubectl rollout status deployment/sre-db -n "$DISPOSABLE_NAMESPACE" --timeout=90s

# Step 4: Wait for API replicas
log_info "Waiting for SRE API rollout (timeout: 120s)..."
kubectl rollout status deployment/sre-api -n "$DISPOSABLE_NAMESPACE" --timeout=120s

# Step 5: Post-deployment safety validation
assert_no_pvc_in_disposable_ns
assert_protected_pvcs_intact

# Step 6: Verify endpoint readiness
log_info "Verifying SRE API pod readiness..."
READY_REPLICAS="$(kubectl get deployment sre-api -n "$DISPOSABLE_NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
EXPECTED_REPLICAS="$(kubectl get deployment sre-api -n "$DISPOSABLE_NAMESPACE" -o jsonpath='{.spec.replicas}')"

if [[ "$READY_REPLICAS" != "$EXPECTED_REPLICAS" ]]; then
  log_err "SRE API replicas not ready: $READY_REPLICAS/$EXPECTED_REPLICAS"
  exit 1
fi

log_pass "SRE lab fixture successfully deployed and ready: $READY_REPLICAS/$EXPECTED_REPLICAS pods running."
