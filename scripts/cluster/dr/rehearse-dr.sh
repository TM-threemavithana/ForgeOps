#!/usr/bin/env bash
# ForgeOps Gate G13 - Complete End-to-End Disaster Recovery & Restoration Rehearsal
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

TARGET_NS="${1:-$DISPOSABLE_DR_NAMESPACE}"
TEARDOWN_AFTER="${2:-no}"
MODE="${3:-execute}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-namespace)
      TARGET_NS="$2"; shift 2 ;;
    --teardown)
      TEARDOWN_AFTER="yes"; shift ;;
    --dry-run|--validate-only)
      MODE="--validate-only"; shift ;;
    *)
      shift ;;
  esac
done

echo "======================================================================="
echo "ForgeOps G13: End-to-End Disaster Recovery Drill & Rehearsal"
echo "Target Namespace:      $TARGET_NS"
echo "Teardown On Success:   $TEARDOWN_AFTER"
echo "======================================================================="

# Preflight validation
run_dr_preflight_guards "$TARGET_NS"

if [[ "$MODE" == "--validate-only" ]]; then
  log_pass "DR rehearsal validation check passed (dry-run)."
  exit 0
fi

E2E_T_START="$(date +%s%N)"

# Step 1: Provision disposable lab fixture with synthetic data
log_info "Step 1: Provisioning disposable DR lab fixture and synthetic database..."
bash "${SCRIPT_DIR}/setup-dr-lab.sh" "$TARGET_NS"

# Step 2: Generate host-side backup with manifest and checksum
log_info "Step 2: Generating host-side PostgreSQL 16 custom backup..."
BACKUP_OUTPUT="$(bash "${SCRIPT_DIR}/backup-db.sh" --source-namespace "$TARGET_NS" --db-name "forgetasks")"
echo "$BACKUP_OUTPUT"

BACKUP_FILE="$(echo "$BACKUP_OUTPUT" | grep -o 'Backup Archive:  .*' | awk '{print $3}' || true)"
MANIFEST_FILE="$(echo "$BACKUP_OUTPUT" | grep -o 'Manifest:        .*' | awk '{print $2}' || true)"
DUMP_DURATION_MS="$(echo "$BACKUP_OUTPUT" | grep -o 'Duration:        [0-9]* ms' | awk '{print $2}' || echo "0")"

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  log_err "CRITICAL: Backup file was not generated or located!"
  exit 1
fi

# Step 3: Verify archive integrity and cryptographic hash
log_info "Step 3: Verifying backup archive and manifest integrity..."
bash "${SCRIPT_DIR}/verify-backup.sh" "$MANIFEST_FILE"

# Step 4: Restore backup into fresh target database instance
log_info "Step 4: Restoring backup into fresh isolated target database..."
RESTORE_OUTPUT="$(bash "${SCRIPT_DIR}/restore-db.sh" "$BACKUP_FILE" --target-namespace "$TARGET_NS" --target-db "forgetasks")"
echo "$RESTORE_OUTPUT"

RESTORE_DURATION_MS="$(echo "$RESTORE_OUTPUT" | grep -o 'Restore Time:      [0-9]* ms' | awk '{print $3}' || echo "0")"
BACKUP_AGE_SECONDS="$(echo "$RESTORE_OUTPUT" | grep -o 'Backup Age (RPO):  [0-9]* seconds' | awk '{print $4}' || echo "0")"

# Step 5: Deploy ForgeTasks API only after target database restoration is fully verified
log_info "Step 5: Deploying ForgeTasks API (dr-api) against restored database..."
kubectl apply \
  -f "${REPO_ROOT}/platform/dr-lab/api-configmap.yaml" \
  -f "${REPO_ROOT}/platform/dr-lab/api-service.yaml" \
  -f "${REPO_ROOT}/platform/dr-lab/api-deployment.yaml" \
  -n "$TARGET_NS"

log_info "Waiting for dr-api deployment rollout to complete (up to 120s)..."
kubectl rollout status deployment/dr-api -n "$TARGET_NS" --timeout=120s

# Step 6: Application-level smoke test via REST API queries against restored database
log_info "Step 6: Conducting application-level REST API smoke test against restored database..."
API_POD="$(kubectl get pods -n "$TARGET_NS" -l app=dr-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "$API_POD" ]]; then
  log_err "CRITICAL: No running dr-api Pod found in '$TARGET_NS'!"
  exit 1
fi
log_info "Identified running workload pod: $API_POD"

API_PORT=18083
API_PF_LOG="$(mktemp)"
kubectl port-forward -n "$TARGET_NS" "pod/${API_POD}" "${API_PORT}:8080" >"$API_PF_LOG" 2>&1 &
API_PF_PID=$!
sleep 2

kill_api_pf() {
  kill -9 "$API_PF_PID" >/dev/null 2>&1 || true
  rm -f "$API_PF_LOG"
}
trap kill_api_pf EXIT INT TERM ERR

# A: Probe actuator health (with connection retry loop for port-forward readiness)
log_info "Verifying API Actuator health endpoint..."
ACTUATOR_HEALTH_UP=false
for attempt in $(seq 1 15); do
  if curl -sf "http://127.0.0.1:${API_PORT}/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then
    ACTUATOR_HEALTH_UP=true
    break
  fi
  sleep 1
done

if [[ "$ACTUATOR_HEALTH_UP" != "true" ]]; then
  log_err "CRITICAL: API actuator health check failed! Endpoint did not return status: UP."
  log_err "Port-forward log output:"
  cat "$API_PF_LOG" >&2 || true
  exit 1
fi
log_pass "Actuator health verified: UP (connected to restored database)."

# B: Authenticated REST queries for projects across accounts
log_info "Querying /api/v1/projects with synthetic dr_admin credentials..."
ADMIN_AUTH_HEADER="Authorization: Basic $(printf '%s:%s' 'dr_admin' 'Password123!' | base64 | tr -d '\r\n')"
ADMIN_PROJECTS_RESP="$(curl -sf -H "$ADMIN_AUTH_HEADER" "http://127.0.0.1:${API_PORT}/api/v1/projects" || true)"

if [[ -z "$ADMIN_PROJECTS_RESP" ]]; then
  log_err "CRITICAL: GET /api/v1/projects (dr_admin) returned empty response!"
  exit 1
fi

if ! echo "$ADMIN_PROJECTS_RESP" | grep -q "DR Verification Project Alpha"; then
  log_err "CRITICAL: Restored database missing expected project 'DR Verification Project Alpha' for dr_admin!"
  exit 1
fi
log_pass "GET /api/v1/projects (dr_admin) verified: 'DR Verification Project Alpha' present."

log_info "Querying /api/v1/projects with synthetic dr_user credentials..."
USER_AUTH_HEADER="Authorization: Basic $(printf '%s:%s' 'dr_user' 'Password123!' | base64 | tr -d '\r\n')"
USER_PROJECTS_RESP="$(curl -sf -H "$USER_AUTH_HEADER" "http://127.0.0.1:${API_PORT}/api/v1/projects" || true)"

if [[ -z "$USER_PROJECTS_RESP" ]]; then
  log_err "CRITICAL: GET /api/v1/projects (dr_user) returned empty response!"
  exit 1
fi

if ! echo "$USER_PROJECTS_RESP" | grep -q "DR Rehearsal Project Beta"; then
  log_err "CRITICAL: Restored database missing expected project 'DR Rehearsal Project Beta' for dr_user!"
  exit 1
fi
log_pass "GET /api/v1/projects (dr_user) verified: 'DR Rehearsal Project Beta' present."

# C: Authenticated REST query for tasks under project
ALPHA_PROJECT_ID="d1000000-0000-0000-0000-000000000001"
log_info "Querying /api/v1/projects/${ALPHA_PROJECT_ID}/tasks with synthetic dr_admin credentials..."
TASKS_RESP="$(curl -sf -H "$ADMIN_AUTH_HEADER" "http://127.0.0.1:${API_PORT}/api/v1/projects/${ALPHA_PROJECT_ID}/tasks" || true)"

if [[ -z "$TASKS_RESP" ]]; then
  log_err "CRITICAL: GET /api/v1/projects/${ALPHA_PROJECT_ID}/tasks returned empty response!"
  exit 1
fi

if ! echo "$TASKS_RESP" | grep -q "Verify Backup Integrity"; then
  log_err "CRITICAL: Restored database missing expected task 'Verify Backup Integrity'!"
  exit 1
fi
if ! echo "$TASKS_RESP" | grep -q "Rehearse Scratch Restore"; then
  log_err "CRITICAL: Restored database missing expected task 'Rehearse Scratch Restore'!"
  exit 1
fi
log_pass "GET /api/v1/projects/{id}/tasks verified: synthetic tasks present in restored database."

# D: Negative authentication check (security regression guard)
log_info "Executing negative authentication check (invalid credentials)..."
INVALID_AUTH_HEADER="Authorization: Basic $(printf '%s:%s' 'dr_admin' 'InvalidPassword' | base64)"
HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -H "$INVALID_AUTH_HEADER" "http://127.0.0.1:${API_PORT}/api/v1/projects" || true)"
if [[ "$HTTP_CODE" != "401" ]]; then
  log_err "SECURITY FAILURE: Invalid credentials returned HTTP $HTTP_CODE (expected 401 Unauthorized)!"
  exit 1
fi
log_pass "Negative authentication check confirmed: 401 Unauthorized for invalid credentials."

kill_api_pf
trap - EXIT INT TERM ERR

E2E_T_END="$(date +%s%N)"
E2E_DURATION_MS=$(( (E2E_T_END - E2E_T_START) / 1000000 ))

# Step 7: Verify original backup file preservation
log_info "Step 7: Verifying backup file remains intact post-rehearsal..."
if [[ ! -f "$BACKUP_FILE" ]]; then
  log_err "CRITICAL FAILURE: Backup archive '$BACKUP_FILE' was removed!"
  exit 1
fi
log_pass "Backup archive preserved at: $BACKUP_FILE"

# Step 8: Optional teardown
if [[ "$TEARDOWN_AFTER" == "yes" ]]; then
  log_info "Step 8: Executing safe teardown of disposable namespace '$TARGET_NS'..."
  bash "${SCRIPT_DIR}/teardown-dr-lab.sh" "$TARGET_NS"
else
  log_info "Step 8: Disposable namespace '$TARGET_NS' preserved for inspection (use teardown-dr-lab.sh to clean up)."
fi

# Final protected PVC validation
assert_protected_pvcs_intact

echo "======================================================================="
log_pass "ALL DISASTER RECOVERY REHEARSAL CHECKS PASSED!"
echo "Backup Archive:        $BACKUP_FILE"
echo "Target Namespace:      $TARGET_NS"
echo "Dump Duration:         ${DUMP_DURATION_MS} ms"
echo "Restore Execution:     ${RESTORE_DURATION_MS} ms (pg_restore only)"
echo "Backup Age (RPO):      ${BACKUP_AGE_SECONDS} seconds"
echo "End-to-End Recovery:   ${E2E_DURATION_MS} ms (rehearsal start to API ready)"
echo "Protected PVCs:        100% Intact"
echo "======================================================================="
