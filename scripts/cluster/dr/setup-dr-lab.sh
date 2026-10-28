#!/usr/bin/env bash
# ForgeOps Gate G13 - Setup Disposable Disaster Recovery Lab Fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

TARGET_NS="${1:-$DISPOSABLE_DR_NAMESPACE}"
MODE="${2:-setup}"

echo "======================================================================="
echo "ForgeOps G13: Provision Disposable Disaster Recovery Lab"
echo "Target Namespace:      $TARGET_NS"
echo "Storage Strategy:      ephemeral emptyDir (STRICT ZERO PVCs)"
echo "Workloads:             dr-source-db, dr-target-db"
echo "Flyway Engine:         Authentic Migration Engine (checksum verified)"
echo "Dataset:               Synthetic test accounts, projects, and tasks"
echo "======================================================================="

# Step 1: Preflight guards
run_dr_preflight_guards "$TARGET_NS"

if [[ "$TARGET_NS" != "$DISPOSABLE_DR_NAMESPACE" ]]; then
  log_err "CRITICAL SAFETY REFUSAL: Target namespace '$TARGET_NS' must be '$DISPOSABLE_DR_NAMESPACE'!"
  exit 1
fi

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running setup-dr-lab in validation mode (dry-run)..."
  kubectl kustomize "${REPO_ROOT}/platform/dr-lab" >/dev/null
  log_pass "Kustomize manifest rendering validated successfully."
  exit 0
fi

# Step 2: Ensure namespace exists and record namespace UID
log_info "Ensuring namespace '$TARGET_NS' exists..."
kubectl apply -f "${REPO_ROOT}/platform/dr-lab/namespace.yaml"

NS_UID="$(kubectl get ns "$TARGET_NS" -o jsonpath='{.metadata.uid}')"
echo "$NS_UID" > /tmp/forgeops-dr-lab.ns-uid
chmod 0600 /tmp/forgeops-dr-lab.ns-uid
log_info "Recorded disposable lab namespace UID: $NS_UID"

# Step 3: Generate dynamic ephemeral credentials & Create Secret FIRST (prevents race condition)
log_info "Generating dynamic ephemeral credentials and creating Secret BEFORE deploying workloads..."
EPHEMERAL_DB_PASS="dr-lab-$(openssl rand -hex 16)"

kubectl create secret generic dr-db-secret \
  -n "$TARGET_NS" \
  --from-literal=postgres-password="$EPHEMERAL_DB_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
log_pass "Secret dr-db-secret established before Deployment scheduling."

# Step 4: Deploy database workloads declaratively via Kustomize
log_info "Applying declarative manifests for $TARGET_NS..."
kubectl apply -k "${REPO_ROOT}/platform/dr-lab"

# Step 5: Wait for database instances to become ready
log_info "Waiting for dr-source-db deployment to become Ready (up to 90s)..."
kubectl rollout status deployment/dr-source-db -n "$TARGET_NS" --timeout=90s

log_info "Waiting for dr-target-db deployment to become Ready (up to 90s)..."
kubectl rollout status deployment/dr-target-db -n "$TARGET_NS" --timeout=90s

# Step 6: Verify authentication on BOTH instances using the generated credentials
log_info "Verifying database instances authenticate using generated credentials..."
SOURCE_POD="$(kubectl get pods -n "$TARGET_NS" -l app=dr-source-db --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
TARGET_POD="$(kubectl get pods -n "$TARGET_NS" -l app=dr-target-db --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

if ! kubectl exec "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -U forgeuser -d forgetasks -c "SELECT 1;" >/dev/null 2>&1; then
  log_err "CRITICAL: dr-source-db failed to authenticate with generated credentials!"
  exit 1
fi
if ! kubectl exec "$TARGET_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -U forgeuser -d forgetasks -c "SELECT 1;" >/dev/null 2>&1; then
  log_err "CRITICAL: dr-target-db failed to authenticate with generated credentials!"
  exit 1
fi
log_pass "Authentication confirmed on both dr-source-db and dr-target-db."

# Step 7: Initialize source database using authentic Flyway migration runner
log_info "Initializing source database with authentic Flyway migration engine..."
LOCAL_SRC_PORT=15432
kubectl port-forward -n "$TARGET_NS" "pod/${SOURCE_POD}" "${LOCAL_SRC_PORT}:5432" >/dev/null 2>&1 &
SRC_PF_PID=$!
sleep 2

kill_src_pf() {
  kill -9 "$SRC_PF_PID" >/dev/null 2>&1 || true
}
trap kill_src_pf EXIT INT TERM ERR

run_flyway_migration_runner "migrate" "127.0.0.1" "$LOCAL_SRC_PORT" "forgetasks" "forgeuser" "$EPHEMERAL_DB_PASS"
kill_src_pf
trap - EXIT INT TERM ERR

# Verify Flyway migration history was genuinely recorded
REAL_MIGRATIONS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -v ON_ERROR_STOP=1 -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM flyway_schema_history WHERE success=true;" | xargs)"
if [[ "$REAL_MIGRATIONS" -lt 1 ]]; then
  log_err "CRITICAL: Flyway migration failed to record genuine history in source database!"
  exit 1
fi
log_pass "Source database schema migrated via Flyway (authentic checksum and history recorded)."

# Step 8: Insert synthetic accounts, projects, tasks
log_info "Seeding synthetic test dataset into source database..."
kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" \
  psql -U forgeuser -d forgetasks -v ON_ERROR_STOP=1 < "${REPO_ROOT}/platform/dr-lab/synthetic-seed.sql"

# Step 9: Verify source data inventory
SRC_ACCOUNTS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -v ON_ERROR_STOP=1 -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM accounts;" | xargs)"
SRC_PROJECTS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -v ON_ERROR_STOP=1 -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM projects;" | xargs)"
SRC_TASKS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -v ON_ERROR_STOP=1 -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM tasks;" | xargs)"

log_info "Source Database Seed Inventory:"
log_info "  - accounts: $SRC_ACCOUNTS"
log_info "  - projects: $SRC_PROJECTS"
log_info "  - tasks:    $SRC_TASKS"

if [[ "$SRC_ACCOUNTS" -lt 2 || "$SRC_PROJECTS" -lt 2 || "$SRC_TASKS" -lt 4 ]]; then
  log_err "CRITICAL: Seed dataset verification failed in source database!"
  exit 1
fi
log_pass "Source dataset verified."

# Step 10: Strict zero PVC verification
assert_no_pvc_in_disposable_ns "$TARGET_NS"

# Step 11: Assert protected PVCs intact
assert_protected_pvcs_intact

log_pass "Disposable Disaster Recovery Lab Provisioned Successfully in '$TARGET_NS' (0 PVCs)!"
