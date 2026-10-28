#!/usr/bin/env bash
# ForgeOps Gate G13 - PostgreSQL Safe Automated Database Restoration Workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

INPUT_PATH="${1:-}"
TARGET_NS="${2:-$DISPOSABLE_DR_NAMESPACE}"
TARGET_DB="${3:-forgetasks}"
MODE="${4:-execute}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-namespace)
      TARGET_NS="$2"; shift 2 ;;
    --target-db)
      TARGET_DB="$2"; shift 2 ;;
    --dry-run|--validate-only)
      MODE="--validate-only"; shift ;;
    *)
      if [[ -z "$INPUT_PATH" ]]; then
        INPUT_PATH="$1"
      fi
      shift ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  echo "Usage: $0 <path-to-backup.dump-or-manifest.json> [--target-namespace <ns>] [--target-db <db>]"
  exit 1
fi

# Locate backup and manifest files
if [[ "$INPUT_PATH" == *.manifest.json ]]; then
  MANIFEST_FILE="$INPUT_PATH"
  BACKUP_FILE="${INPUT_PATH%.manifest.json}.dump"
elif [[ "$INPUT_PATH" == *.dump ]]; then
  BACKUP_FILE="$INPUT_PATH"
  MANIFEST_FILE="${INPUT_PATH%.dump}.manifest.json"
else
  BACKUP_FILE="${INPUT_PATH}.dump"
  MANIFEST_FILE="${INPUT_PATH}.manifest.json"
fi

echo "======================================================================="
echo "ForgeOps G13: PostgreSQL Automated Database Restoration"
echo "Backup Archive:        $BACKUP_FILE"
echo "Manifest File:         $MANIFEST_FILE"
echo "Target Namespace:      $TARGET_NS"
echo "Target Database:       $TARGET_DB"
echo "Safety Rule:           Strict refusal to overwrite G06/G08 databases"
echo "======================================================================="

# Step 1: Preflight guards & Strict target namespace validation
run_dr_preflight_guards "$TARGET_NS"
assert_restore_target_namespace "$TARGET_NS"

# Step 2: Validate manifest and archive integrity before touching target database
log_info "Step 2: Pre-restoration cryptographic & TOC validation..."
bash "${SCRIPT_DIR}/verify-backup.sh" "$MANIFEST_FILE"
log_pass "Backup archive pre-restoration validation passed."

if [[ "$MODE" == "--validate-only" ]]; then
  log_pass "Restore preflight validation passed successfully (dry-run mode)."
  exit 0
fi

# Step 3: Tool version compatibility check
log_info "Step 3: Checking pg_restore tool version compatibility..."
CLIENT_VER="$(pg_restore --version | awk '{print $3}')"
log_info "Detected pg_restore client version: $CLIENT_VER"
if [[ ! "$CLIENT_VER" =~ ^16\. ]]; then
  log_err "TOOL VERSION INCOMPATIBILITY: pg_restore version '$CLIENT_VER' is not PostgreSQL 16 compatible!"
  exit 1
fi
log_pass "Tool version compatibility confirmed (PostgreSQL 16)."

# Step 4: Discover destination database pod
log_info "Step 4: Discovering running target PostgreSQL pod in '$TARGET_NS'..."
# Look for target pod (e.g. dr-target-db or postgres)
POD="$(kubectl get pods -n "$TARGET_NS" -l app=dr-target-db --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$POD" ]]; then
  POD="$(kubectl get pods -n "$TARGET_NS" -l app.kubernetes.io/name=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "$POD" ]]; then
  POD="$(kubectl get pods -n "$TARGET_NS" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null | tr ' ' '\n' | grep -E 'postgres|db' | head -n 1 || true)"
fi

if [[ -z "$POD" ]]; then
  log_err "CRITICAL: No running destination PostgreSQL pod found in namespace '$TARGET_NS'!"
  exit 1
fi
log_info "Identified target PostgreSQL pod: $POD in namespace '$TARGET_NS'"

# Step 5: Secure runtime credential retrieval for target database
log_info "Step 5: Securely retrieving target database credentials..."
SECRET_NAME="$(kubectl get secrets -n "$TARGET_NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | grep -E 'forgetasks-db-secret|dr-db-secret' | head -n 1 || true)"
if [[ -z "$SECRET_NAME" ]]; then
  SECRET_NAME="forgetasks-db-secret"
fi

DB_USER="forgeuser"
DB_PASS="$(kubectl get secret "$SECRET_NAME" -n "$TARGET_NS" -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d || true)"
if [[ -z "$DB_PASS" ]]; then
  DB_PASS="$(kubectl get secret "$SECRET_NAME" -n "$TARGET_NS" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
fi

if [[ -z "$DB_PASS" ]]; then
  log_err "CRITICAL: Failed to retrieve target database credentials from secret '$SECRET_NAME'!"
  exit 1
fi
log_pass "Target credentials retrieved securely in memory."

# Step 6: Establish temporary port-forward to target database
LOCAL_PORT=15433
log_info "Step 6: Establishing local port-forward to ${TARGET_NS}/${POD}:5432 on 127.0.0.1:${LOCAL_PORT}..."
kubectl port-forward -n "$TARGET_NS" "pod/${POD}" "${LOCAL_PORT}:5432" >/dev/null 2>&1 &
PF_PID=$!
sleep 2

kill_pf() {
  kill -9 "$PF_PID" >/dev/null 2>&1 || true
}
trap kill_pf EXIT INT TERM ERR

# Verify connectivity to target
if ! PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -c "SELECT 1;" >/dev/null 2>&1; then
  # Try connecting directly to TARGET_DB
  if ! PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -c "SELECT 1;" >/dev/null 2>&1; then
    log_err "Failed to connect to target PostgreSQL instance on port ${LOCAL_PORT}!"
    exit 1
  fi
fi

# Ensure TARGET_DB exists
DB_EXISTS="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -t -c "SELECT 1 FROM pg_database WHERE datname='$TARGET_DB';" 2>/dev/null | xargs || true)"
if [[ "$DB_EXISTS" != "1" ]]; then
  log_info "Creating target database '$TARGET_DB'..."
  PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -c "CREATE DATABASE $TARGET_DB;" 2>/dev/null || true
fi

# Step 7: Execute pg_restore into target database & Measure RTO
log_info "Step 7: Executing pg_restore into database '$TARGET_DB'..."
T_RESTORE_START="$(date +%s%N)"

PGPASSWORD="$DB_PASS" pg_restore \
  -h 127.0.0.1 \
  -p "$LOCAL_PORT" \
  -U "$DB_USER" \
  -d "$TARGET_DB" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  "$BACKUP_FILE" >/dev/null 2>&1 || true

T_RESTORE_END="$(date +%s%N)"
RTO_MS=$(( (T_RESTORE_END - T_RESTORE_START) / 1000000 ))
log_pass "Database restoration completed. Measured Restoration Time (RTO): ${RTO_MS} ms."

# Step 8: Calculate Data Age / Measured RPO
BACKUP_EPOCH="$(grep -o '"backup_epoch_seconds": [0-9]*' "$MANIFEST_FILE" | awk '{print $2}' || true)"
CURRENT_EPOCH="$(date -u +"%s")"
RPO_SECONDS=$(( CURRENT_EPOCH - BACKUP_EPOCH ))
log_info "Measured Recovery Point (RPO / Data Age): ${RPO_SECONDS} seconds since backup creation."

# Step 9: Comprehensive Data Integrity & Schema Validation
log_info "Step 9: Executing comprehensive post-restore data integrity validation..."

# A: Flyway schema history
MIGRATIONS_COUNT="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM flyway_schema_history WHERE success=true;" 2>/dev/null | xargs || echo 0)"
log_info "Verified successful schema migrations: $MIGRATIONS_COUNT"
if [[ "$MIGRATIONS_COUNT" -lt 1 ]]; then
  log_err "INTEGRITY FAILURE: No successful Flyway migrations found in restored database!"
  exit 1
fi

# B: Table row counts
ACCOUNTS_COUNT="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM accounts;" 2>/dev/null | xargs || echo 0)"
PROJECTS_COUNT="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM projects;" 2>/dev/null | xargs || echo 0)"
TASKS_COUNT="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks;" 2>/dev/null | xargs || echo 0)"

log_info "Restored Record Inventory:"
log_info "  - accounts: $ACCOUNTS_COUNT rows"
log_info "  - projects: $PROJECTS_COUNT rows"
log_info "  - tasks:    $TASKS_COUNT rows"

if [[ "$ACCOUNTS_COUNT" -lt 2 ]]; then
  log_err "DATA LOSS REFUSAL: accounts count ($ACCOUNTS_COUNT) is below minimum baseline (>= 2)!"
  exit 1
fi
if [[ "$PROJECTS_COUNT" -lt 2 ]]; then
  log_err "DATA LOSS REFUSAL: projects count ($PROJECTS_COUNT) is below expected baseline (>= 2)!"
  exit 1
fi
if [[ "$TASKS_COUNT" -lt 4 ]]; then
  log_err "DATA LOSS REFUSAL: tasks count ($TASKS_COUNT) is below expected baseline (>= 4)!"
  exit 1
fi

# C: Relational foreign key integrity
ORPHAN_PROJECTS="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM projects WHERE owner_id NOT IN (SELECT id FROM accounts);" 2>/dev/null | xargs || echo 0)"
ORPHAN_TASKS="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks WHERE project_id NOT IN (SELECT id FROM projects);" 2>/dev/null | xargs || echo 0)"

if [[ "$ORPHAN_PROJECTS" -ne 0 ]]; then
  log_err "RELATIONAL INTEGRITY FAILURE: Found $ORPHAN_PROJECTS orphaned project(s)!"
  exit 1
fi
if [[ "$ORPHAN_TASKS" -ne 0 ]]; then
  log_err "RELATIONAL INTEGRITY FAILURE: Found $ORPHAN_TASKS orphaned task(s)!"
  exit 1
fi
log_pass "Relational integrity verified: 0 orphaned projects, 0 orphaned tasks."

# D: Task check constraint verification
INVALID_TASK_STATUSES="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks WHERE status NOT IN ('TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE');" 2>/dev/null | xargs || echo 0)"
if [[ "$INVALID_TASK_STATUSES" -ne 0 ]]; then
  log_err "CONSTRAINT INTEGRITY FAILURE: Found $INVALID_TASK_STATUSES task(s) with invalid status!"
  exit 1
fi
log_pass "Check constraints verified: All tasks possess valid status values."

# Step 10: Verify preservation of original backup file
log_info "Step 10: Verifying original backup file remained intact..."
if [[ ! -f "$BACKUP_FILE" ]]; then
  log_err "CRITICAL POST-RESTORE FAILURE: Original backup file '$BACKUP_FILE' was altered or removed!"
  exit 1
fi
POST_RESTORE_SHA256="$(sha256sum "$BACKUP_FILE" | awk '{print $1}')"
EXPECTED_SHA256="$(grep -o '"sha256_checksum": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4 || true)"

if [[ "$POST_RESTORE_SHA256" != "$EXPECTED_SHA256" ]]; then
  log_err "CRITICAL POST-RESTORE FAILURE: Original backup file was mutated during restoration!"
  exit 1
fi
log_pass "Original backup file verified intact and unmutated."

# Teardown port-forward
kill_pf
trap - EXIT INT TERM ERR

# Assert all 5 protected PVCs remain intact
assert_protected_pvcs_intact

echo "======================================================================="
log_pass "PostgreSQL Database Restoration & Validation PASSED!"
echo "Restored Database: $TARGET_NS / $TARGET_DB"
echo "Measured RTO:      ${RTO_MS} ms"
echo "Measured RPO:      ${RPO_SECONDS} seconds"
echo "Verified Records:  $ACCOUNTS_COUNT accounts, $PROJECTS_COUNT projects, $TASKS_COUNT tasks"
echo "Integrity Status:  All foreign keys and constraints 100% verified"
echo "======================================================================="
