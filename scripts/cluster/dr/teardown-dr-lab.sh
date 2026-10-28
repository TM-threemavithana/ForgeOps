#!/usr/bin/env bash
# ForgeOps Gate G13 - Hardened Teardown for Disposable Disaster Recovery Lab
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-dr.sh"

TARGET_NS="$DISPOSABLE_DR_NAMESPACE"
MODE="teardown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate-only|--dry-run)
      MODE="--validate-only"; shift ;;
    *)
      if [[ "$1" != --* ]]; then
        TARGET_NS="$1"
      fi
      shift ;;
  esac
done

echo "======================================================================="
echo "ForgeOps G13: Disposable Disaster Recovery Lab Teardown & Audit"
echo "Target Namespace: $TARGET_NS"
echo "======================================================================="

# Step 1: Preflight guards
run_dr_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running teardown-dr-lab in validation mode (no deletion)..."
  log_pass "Teardown preflight validation passed."
  exit 0
fi

if ! kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
  log_info "Namespace '$TARGET_NS' does not exist; nothing to tear down."
  assert_protected_pvcs_intact
  exit 0
fi

# Step 2: Validate exact namespace identity and ownership labels
log_info "Auditing namespace metadata and ownership labels..."
NS_NAME="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.name}')"
if [[ "$NS_NAME" != "$DISPOSABLE_DR_NAMESPACE" ]]; then
  log_err "CRITICAL REFUSAL: Target namespace name '$NS_NAME' does not match mandated '$DISPOSABLE_DR_NAMESPACE'!"
  exit 1
fi

DISPOSABLE_LABEL="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/disposable}' 2>/dev/null || true)"
ENV_LABEL="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/environment}' 2>/dev/null || true)"

if [[ "$DISPOSABLE_LABEL" != "true" || "$ENV_LABEL" != "dr-lab" ]]; then
  log_err "CRITICAL REFUSAL: Namespace '$TARGET_NS' is missing required disposable labels (disposable=$DISPOSABLE_LABEL, env=$ENV_LABEL)!"
  log_err "Preserving namespace and halting teardown to protect unverified resources."
  exit 1
fi

# Verify namespace UID recorded during setup (mandatory - never skipped)
UID_FILE="${FORGEOPS_DR_UID_FILE:-/tmp/forgeops-dr-lab.ns-uid}"
if [[ ! -f "$UID_FILE" ]]; then
  log_err "CRITICAL REFUSAL: Missing recorded namespace UID file '$UID_FILE'!"
  log_err "Teardown requires a valid recorded UID to confirm namespace identity. Halting teardown."
  exit 1
fi

EXPECTED_UID="$(cat "$UID_FILE" | tr -d ' \r\n')"
if [[ -z "$EXPECTED_UID" ]]; then
  log_err "CRITICAL REFUSAL: Recorded namespace UID file '$UID_FILE' is empty!"
  log_err "Teardown requires a non-empty recorded UID. Halting teardown."
  exit 1
fi

CURRENT_UID="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
if [[ "$CURRENT_UID" != "$EXPECTED_UID" ]]; then
  log_err "NAMESPACE IDENTITY MISMATCH: Current namespace UID '$CURRENT_UID' does not match recorded UID '$EXPECTED_UID'!"
  log_err "Halting teardown to prevent terminating an unexpected namespace instance."
  exit 1
fi
log_pass "Namespace UID verified: $CURRENT_UID"

# Step 3: Complete resource inventory audit against allowlist
log_info "Performing complete resource inventory audit in '$TARGET_NS' against allowlist..."

# A: Require zero PVCs
assert_no_pvc_in_disposable_ns "$TARGET_NS"

# B: Check for forbidden resource types (StatefulSets, DaemonSets, Jobs, CronJobs, Ingresses)
STS_COUNT="$(kubectl get statefulsets -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$STS_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $STS_COUNT StatefulSet(s) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

DS_COUNT="$(kubectl get daemonsets -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$DS_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $DS_COUNT DaemonSet(s) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

JOB_COUNT="$(kubectl get jobs -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$JOB_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $JOB_COUNT Job(s) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

CRONJOB_COUNT="$(kubectl get cronjobs -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$CRONJOB_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $CRONJOB_COUNT CronJob(s) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

ING_COUNT="$(kubectl get ingress -n "$TARGET_NS" --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$ING_COUNT" -gt 0 ]]; then
  log_err "UNEXPECTED RESOURCES: Found $ING_COUNT Ingress(es) in '$TARGET_NS'! Halting teardown."
  exit 1
fi

# C: Check Deployments against strict allowlist (only dr-source-db, dr-target-db, dr-api permitted)
DEP_LIST="$(kubectl get deployments -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for dep in $DEP_LIST; do
  if [[ "$dep" != "dr-source-db" && "$dep" != "dr-target-db" && "$dep" != "dr-api" ]]; then
    log_err "UNEXPECTED DEPLOYMENT: Found unapproved deployment '$dep' in '$TARGET_NS'! Preserving namespace and stopping."
    exit 1
  fi
done

# D: Check Services against strict allowlist (only dr-source-db, dr-target-db, dr-api permitted)
SVC_LIST="$(kubectl get services -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for svc in $SVC_LIST; do
  if [[ "$svc" != "dr-source-db" && "$svc" != "dr-target-db" && "$svc" != "dr-api" ]]; then
    log_err "UNEXPECTED SERVICE: Found unapproved service '$svc' in '$TARGET_NS'! Preserving namespace and stopping."
    exit 1
  fi
done

# E: Check Secrets against strict allowlist (dr-db-secret and standard ServiceAccount tokens)
SECRET_NAMES="$(kubectl get secrets -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for sec in $SECRET_NAMES; do
  if [[ "$sec" == "dr-db-secret" ]]; then
    continue
  fi
  SEC_TYPE="$(kubectl get secret "$sec" -n "$TARGET_NS" -o jsonpath='{.type}' 2>/dev/null || true)"
  if [[ "$SEC_TYPE" == "kubernetes.io/service-account-token" || "$sec" == default-token-* || "$sec" == dr-serviceaccount-token-* ]]; then
    continue
  fi
  log_err "UNEXPECTED SECRET: Found unapproved secret '$sec' (type '$SEC_TYPE') in '$TARGET_NS'! Preserving namespace and stopping."
  exit 1
done

# F: Check ConfigMaps against strict allowlist (kube-root-ca.crt, dr-api-config)
CM_LIST="$(kubectl get configmaps -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for cm in $CM_LIST; do
  if [[ "$cm" != "kube-root-ca.crt" && "$cm" != "dr-api-config" ]]; then
    log_err "UNEXPECTED CONFIGMAP: Found unapproved configmap '$cm' in '$TARGET_NS'! Preserving namespace and stopping."
    exit 1
  fi
done

# G: Check ServiceAccounts against strict allowlist (default, dr-serviceaccount)
SA_LIST="$(kubectl get serviceaccounts -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
for sa in $SA_LIST; do
  if [[ "$sa" != "default" && "$sa" != "dr-serviceaccount" ]]; then
    log_err "UNEXPECTED SERVICEACCOUNT: Found unapproved serviceaccount '$sa' in '$TARGET_NS'! Preserving namespace and stopping."
    exit 1
  fi
done

# Step 4: Record host backup files before deletion to ensure preservation
BEFORE_BACKUP_COUNT=0
if [[ -d "$DEFAULT_BACKUP_DIR" ]]; then
  BEFORE_BACKUP_COUNT="$(find "$DEFAULT_BACKUP_DIR" -type f \( -name "*.dump" -o -name "*.manifest.json" \) 2>/dev/null | wc -l || echo 0)"
fi

# Step 5: Graceful deletion without --force or finalizer tampering
log_info "Deleting namespace '$TARGET_NS' gracefully (standard deletion, no --force, no finalizer tampering)..."
kubectl delete namespace "$TARGET_NS" --timeout=120s

# Step 6: Confirm deletion completed
if kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
  log_warn "Namespace is still terminating; waiting up to 30s for finalization..."
  kubectl wait --for=delete "namespace/${TARGET_NS}" --timeout=30s || {
    log_err "Namespace '$TARGET_NS' failed to terminate within timeout! Preserving state for operator review."
    exit 1
  }
fi

rm -f "$UID_FILE"

# Step 7: Verify preservation of host backup archives
if [[ -d "$DEFAULT_BACKUP_DIR" ]]; then
  AFTER_BACKUP_COUNT="$(find "$DEFAULT_BACKUP_DIR" -type f \( -name "*.dump" -o -name "*.manifest.json" \) 2>/dev/null | wc -l || echo 0)"
  if [[ "$AFTER_BACKUP_COUNT" -lt "$BEFORE_BACKUP_COUNT" ]]; then
    log_err "CRITICAL POST-TEARDOWN WARNING: Host backup archives count dropped from $BEFORE_BACKUP_COUNT to $AFTER_BACKUP_COUNT!"
    exit 1
  fi
  log_pass "Host backup archives preserved in $DEFAULT_BACKUP_DIR ($AFTER_BACKUP_COUNT files)."
fi

# Step 8: Final verification of all 5 protected PVCs
assert_protected_pvcs_intact

log_pass "Disposable DR lab teardown completed cleanly and safely. All protected resources verified intact."
