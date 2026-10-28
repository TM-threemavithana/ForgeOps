#!/usr/bin/env bash
# ForgeOps Gate G12 - SRE Common Utilities & Fail-Closed Safety Guards
set -euo pipefail

# Expected protected PVC UIDs
EXPECTED_G06_PVC_UID="84853fb3-4d13-43a9-bc62-973c3be3c90c"
EXPECTED_G08_PVC_UID="b5ea8ec9-47e8-4979-afdb-621f2e3c63b8"
EXPECTED_G09_PVC_UID="cd64e090-2c69-49b3-a389-de5841ce06d6"
EXPECTED_G10_PVC_UID="23468366-7394-4f2d-be1f-2a640d6f12c5"
EXPECTED_G11_PVC_UID="092b6655-6617-467c-b546-69e201a0ba8a"

DISPOSABLE_NAMESPACE="forgeops-sre-lab"

log_info() {
  echo -e "\033[0;34m[SRE-INFO]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

log_warn() {
  echo -e "\033[0;33m[SRE-WARN]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

log_err() {
  echo -e "\033[0;31m[SRE-FAIL]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*" >&2
}

log_pass() {
  echo -e "\033[0;32m[SRE-PASS]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

# Verify cluster connectivity
assert_cluster_connectivity() {
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$ctx" != "kind-forgeops" ]]; then
    log_err "Safety check failed: Active context is '$ctx', expected 'kind-forgeops'"
    return 1
  fi
  kubectl cluster-info >/dev/null 2>&1 || {
    log_err "Failed to connect to Kubernetes cluster with context 'kind-forgeops'"
    return 1
  }
}

# Fail-closed namespace guard
assert_target_namespace() {
  local target_ns="${1:-}"
  if [[ -z "$target_ns" ]]; then
    log_err "Target namespace is empty! Refusing to proceed."
    return 1
  fi

  if [[ "$target_ns" != "$DISPOSABLE_NAMESPACE" ]]; then
    log_err "SAFETY VIOLATION: Target namespace '$target_ns' is NOT the approved disposable namespace '$DISPOSABLE_NAMESPACE'!"
    log_err "Refusing to inject fault or execute mutation outside '$DISPOSABLE_NAMESPACE'."
    return 1
  fi

  # Explicit negative protection list
  local forbidden=("forgeops-dev" "forgeops-gitops-rehearsal" "forgeops-observability" "kube-system" "argocd" "default")
  for bad in "${forbidden[@]}"; do
    if [[ "$target_ns" == "$bad" ]]; then
      log_err "CRITICAL SAFETY ABORT: Namespace '$target_ns' is on the protected blacklist!"
      return 1
    fi
  done
}

# Verify protected PVC UIDs
assert_protected_pvcs_intact() {
  log_info "Verifying protected PVC UIDs across cluster..."

  local g06_uid g08_uid g09_uid g10_uid g11_uid

  g06_uid="$(kubectl get pvc postgres-storage-forgetasks-db-0 -n forgeops-dev -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  g08_uid="$(kubectl get pvc postgres-storage-forgetasks-rehearsal-db-0 -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  g09_uid="$(kubectl get pvc prometheus-g09-monitoring-kube-promet-prometheus-db-prometheus-g09-monitoring-kube-promet-prometheus-0 -n forgeops-observability -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  g10_uid="$(kubectl get pvc storage-loki-0 -n forgeops-observability -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  g11_uid="$(kubectl get pvc storage-tempo-0 -n forgeops-observability -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"

  local failed=0
  if [[ "$g06_uid" != "$EXPECTED_G06_PVC_UID" ]]; then
    log_err "G06 PostgreSQL PVC UID mismatch or missing! Expected '$EXPECTED_G06_PVC_UID', got '$g06_uid'"
    failed=1
  fi
  if [[ "$g08_uid" != "$EXPECTED_G08_PVC_UID" ]]; then
    log_err "G08 PostgreSQL PVC UID mismatch or missing! Expected '$EXPECTED_G08_PVC_UID', got '$g08_uid'"
    failed=1
  fi
  if [[ "$g09_uid" != "$EXPECTED_G09_PVC_UID" ]]; then
    log_err "G09 Prometheus PVC UID mismatch or missing! Expected '$EXPECTED_G09_PVC_UID', got '$g09_uid'"
    failed=1
  fi
  if [[ "$g10_uid" != "$EXPECTED_G10_PVC_UID" ]]; then
    log_err "G10 Loki PVC UID mismatch or missing! Expected '$EXPECTED_G10_PVC_UID', got '$g10_uid'"
    failed=1
  fi
  if [[ "$g11_uid" != "$EXPECTED_G11_PVC_UID" ]]; then
    log_err "G11 Tempo PVC UID mismatch or missing! Expected '$EXPECTED_G11_PVC_UID', got '$g11_uid'"
    failed=1
  fi

  if [[ "$failed" -ne 0 ]]; then
    log_err "Protected PVC validation FAILED! Halting immediately to protect state."
    return 1
  fi

  log_pass "All 5 protected PVCs validated with exact expected UIDs."
}

# Verify no persistent volumes in disposable namespace
assert_no_pvc_in_disposable_ns() {
  local pvc_count
  pvc_count="$(kubectl get pvc -n "$DISPOSABLE_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo 0)"
  if [[ "$pvc_count" -gt 0 ]]; then
    log_err "Found $pvc_count PVC(s) in disposable namespace '$DISPOSABLE_NAMESPACE'! Expected 0 (must use emptyDir)."
    return 1
  fi
  log_pass "Disposable namespace '$DISPOSABLE_NAMESPACE' has 0 PVCs as required."
}

# Comprehensive preflight guard
run_sre_preflight_guards() {
  local target_ns="${1:-$DISPOSABLE_NAMESPACE}"
  log_info "Executing fail-closed SRE safety guards..."
  assert_cluster_connectivity
  assert_target_namespace "$target_ns"
  assert_protected_pvcs_intact
  log_pass "Preflight safety guards verified successfully."
}
