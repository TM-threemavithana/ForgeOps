#!/usr/bin/env bash
# ForgeOps Gate G13 - Disaster Recovery & Database Backup Common Utilities & Fail-Closed Safety Guards
set -euo pipefail

# Auto-detect ForgeOps lab kubeconfig if not explicitly set
if [[ -z "${KUBECONFIG:-}" && -f "${HOME}/.kube/config-forgeops" ]]; then
  export KUBECONFIG="${HOME}/.kube/config-forgeops"
fi

# Documented protected baseline PVC UIDs (Zero Data Loss Invariant)
EXPECTED_G06_PVC_UID="84853fb3-4d13-43a9-bc62-973c3be3c90c"
EXPECTED_G08_PVC_UID="b5ea8ec9-47e8-4979-afdb-621f2e3c63b8"
EXPECTED_G09_PVC_UID="cd64e090-2c69-49b3-a389-de5841ce06d6"
EXPECTED_G10_PVC_UID="23468366-7394-4f2d-be1f-2a640d6f12c5"
EXPECTED_G11_PVC_UID="092b6655-6617-467c-b546-69e201a0ba8a"

DISPOSABLE_DR_NAMESPACE="forgeops-dr-lab"
DEFAULT_BACKUP_DIR="${FORGEOPS_BACKUP_DIR:-$HOME/.forgeops/backups}"
MIN_FREE_DISK_MB=250

log_info() {
  echo -e "\033[0;34m[DR-INFO]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

log_warn() {
  echo -e "\033[0;33m[DR-WARN]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

log_err() {
  echo -e "\033[0;31m[DR-FAIL]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*" >&2
}

log_pass() {
  echo -e "\033[0;32m[DR-PASS]\033[0m $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"
}

# Verify active Kubernetes context is kind-forgeops
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

# Verify source namespace for backup is an allowlisted lab namespace
assert_backup_source_namespace() {
  local source_ns="${1:-}"
  if [[ -z "$source_ns" ]]; then
    log_err "Backup source namespace is empty! Refusing to proceed."
    return 1
  fi

  local allowlisted=("forgeops-dr-lab" "forgeops-dev" "forgeops-gitops-rehearsal")
  local allowed=0
  for ns in "${allowlisted[@]}"; do
    if [[ "$source_ns" == "$ns" ]]; then
      allowed=1
      break
    fi
  done

  if [[ "$allowed" -ne 1 ]]; then
    log_err "SAFETY REFUSAL: Namespace '$source_ns' is NOT in approved backup source allowlist (${allowlisted[*]})!"
    log_err "Refusing backup from unknown or unverified environment."
    return 1
  fi
}

# Strict guard: Destination for restoration MUST be disposable.
# NEVER allow restore into forgeops-dev, forgeops-gitops-rehearsal, argocd, or system namespaces!
assert_restore_target_namespace() {
  local target_ns="${1:-}"
  if [[ -z "$target_ns" ]]; then
    log_err "Restore target namespace is empty! Refusing to proceed."
    return 1
  fi

  # Explicit hard forbidden list
  local forbidden=("forgeops-dev" "forgeops-gitops-rehearsal" "forgeops-observability" "kube-system" "argocd" "default" "local-path-storage" "kube-public" "kube-node-lease")
  for bad in "${forbidden[@]}"; do
    if [[ "$target_ns" == "$bad" ]]; then
      log_err "CRITICAL SAFETY REFUSAL: Target namespace '$target_ns' is protected!"
      log_err "Never restore over existing dev, rehearsal, gitops, or observability databases."
      return 1
    fi
  done

  if [[ "$target_ns" != "$DISPOSABLE_DR_NAMESPACE" ]]; then
    log_err "SAFETY REFUSAL: Target namespace '$target_ns' is NOT the approved disposable namespace '$DISPOSABLE_DR_NAMESPACE'!"
    log_err "For this rehearsal, restoration is strictly restricted to '$DISPOSABLE_DR_NAMESPACE'."
    return 1
  fi
}

# Verify protected PVC UIDs across the cluster
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

  if [[ "$failed" -eq 1 ]]; then
    log_err "Protected PVC UID check failed! Halting operation immediately to prevent data loss."
    return 1
  fi

  log_pass "All 5 protected PVCs validated with exact expected baseline UIDs."
}

# Verify no PVCs exist in disposable namespace
assert_no_pvc_in_disposable_ns() {
  local target_ns="${1:-$DISPOSABLE_DR_NAMESPACE}"
  local pvc_count
  pvc_count="$(kubectl get pvc -n "$target_ns" --no-headers 2>/dev/null | wc -l || echo 0)"
  if [[ "$pvc_count" -gt 0 ]]; then
    log_err "SAFETY REFUSAL: Found $pvc_count PVC(s) in disposable namespace '$target_ns'!"
    log_err "Disposable DR lab must strictly use ephemeral emptyDir storage. Halting operation."
    return 1
  fi
  log_pass "Verified 0 PVCs in disposable namespace '$target_ns'."
}

# Verify available disk headroom before backup
check_disk_headroom() {
  local dir="${1:-$DEFAULT_BACKUP_DIR}"
  mkdir -p "$dir"
  chmod 0700 "$dir"

  # Check free space in MB on backup filesystem
  local avail_kb
  avail_kb="$(df -k "$dir" | awk 'NR==2 {print $4}')"
  local avail_mb=$(( avail_kb / 1024 ))

  log_info "Backup destination: $dir (available on volume: ${avail_mb} MB)"

  if [[ "$avail_mb" -lt "$MIN_FREE_DISK_MB" ]]; then
    log_err "DISK SPACE REFUSAL: Destination directory '$dir' has only ${avail_mb} MB available, requiring at least ${MIN_FREE_DISK_MB} MB!"
    return 1
  fi

  # Note physical host limitation: WSL virtual drive reports large capacity,
  # but underlying physical Windows C: drive headroom must be preserved.
  log_info "Disk headroom check passed (>= ${MIN_FREE_DISK_MB} MB available)."
}

# Fail-closed preflight guards
run_dr_preflight_guards() {
  local ns="${1:-}"
  log_info "Executing fail-closed Disaster Recovery safety guards..."
  assert_cluster_connectivity
  assert_protected_pvcs_intact
}

# Execute authentic Flyway migration runner
run_flyway_migration_runner() {
  local action="${1:-info}"
  local host="${2:-127.0.0.1}"
  local port="${3:-5432}"
  local db_name="${4:-forgetasks}"
  local db_user="${5:-forgeuser}"
  local db_pass="${6:-}"

  local jdbc_url="jdbc:postgresql://${host}:${port}/${db_name}"
  log_info "Invoking authentic Flyway engine ($action) against $jdbc_url..."

  local api_dir="${REPO_ROOT}/apps/forgetasks-api"
  if [[ ! -f "${api_dir}/mvnw" ]]; then
    log_err "Maven wrapper not found in ${api_dir}!"
    return 1
  fi

  # Pass password via FLYWAY_PASSWORD environment variable to avoid process table exposure
  FLYWAY_PASSWORD="$db_pass" "${api_dir}/mvnw" -q -f "${api_dir}/pom.xml" exec:java \
    -Dexec.mainClass="com.forgeops.forgetasks.FlywayMigrationRunner" \
    -Dexec.args="${action} ${jdbc_url} ${db_user}"
}
