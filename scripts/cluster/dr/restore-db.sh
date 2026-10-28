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
echo "Safety Rule:           Strict refusal to restore outside $DISPOSABLE_DR_NAMESPACE"
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

# Step 4: Discover destination database pod with strict isolation guards
log_info "Step 4: Discovering running target PostgreSQL pod in '$TARGET_NS'..."

# For this rehearsal, target pod MUST strictly belong to deployment/dr-target-db
mapfile -t TARGET_CANDIDATES < <(kubectl get pods -n "$TARGET_NS" -l app=dr-target-db --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v '^$' || true)

if [[ "${#TARGET_CANDIDATES[@]}" -eq 0 ]]; then
  log_err "CRITICAL: No running destination PostgreSQL pod found with app=dr-target-db in '$TARGET_NS'!"
  exit 1
fi
if [[ "${#TARGET_CANDIDATES[@]}" -gt 1 ]]; then
  log_err "CRITICAL: Multiple target database pods found (${#TARGET_CANDIDATES[@]}). Expected exactly 1!"
  exit 1
fi

POD="${TARGET_CANDIDATES[0]}"

# Verify owning Deployment is dr-target-db
OWNER_NAME="$(kubectl get pod "$POD" -n "$TARGET_NS" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)"
if [[ "$OWNER_NAME" != *"dr-target-db"* ]]; then
  log_err "CRITICAL: Target pod '$POD' owner reference '$OWNER_NAME' is not dr-target-db!"
  exit 1
fi

# Verify target pod UID is distinct from any source pod UID
TARGET_POD_UID="$(kubectl get pod "$POD" -n "$TARGET_NS" -o jsonpath='{.metadata.uid}')"
SOURCE_POD_UID="$(kubectl get pods -n "$TARGET_NS" -l app=dr-source-db -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null || true)"

if [[ -n "$SOURCE_POD_UID" && "$TARGET_POD_UID" == "$SOURCE_POD_UID" ]]; then
  log_err "CRITICAL SAFETY REFUSAL: Target Pod UID matches Source Pod UID ($TARGET_POD_UID)! Refusing to restore into source pod."
  exit 1
fi

ROLE_LABEL="$(kubectl get pod "$POD" -n "$TARGET_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/role}' 2>/dev/null || true)"
if [[ "$ROLE_LABEL" == "source" ]]; then
  log_err "CRITICAL SAFETY REFUSAL: Target pod '$POD' carries source role label! Refusing to restore into source pod."
  exit 1
fi

log_info "Identified and verified target PostgreSQL pod: $POD (UID: $TARGET_POD_UID)"

# Step 5: Secure runtime credential retrieval for target database
log_info "Step 5: Securely retrieving target database credentials..."
SECRET_NAME="$(kubectl get secrets -n "$TARGET_NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | grep -E 'forgetasks-db-secret|dr-db-secret' | head -n 1 || true)"
if [[ -z "$SECRET_NAME" ]]; then
  SECRET_NAME="dr-db-secret"
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
log_pass "Target credentials retrieved securely in memory (redacted from logs)."

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

# Verify connectivity to target instance
if ! PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -c "SELECT 1;" >/dev/null 2>&1; then
  if ! PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -c "SELECT 1;" >/dev/null 2>&1; then
    log_err "Failed to authenticate with target PostgreSQL instance on port ${LOCAL_PORT}!"
    exit 1
  fi
fi

# Ensure TARGET_DB exists
DB_EXISTS="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -t -c "SELECT 1 FROM pg_database WHERE datname='$TARGET_DB';" 2>/dev/null | xargs || true)"
if [[ "$DB_EXISTS" != "1" ]]; then
  log_info "Creating target database '$TARGET_DB'..."
  PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "postgres" -c "CREATE DATABASE $TARGET_DB;"
fi

# Strict check: Target database MUST be fresh and empty before restoration
log_info "Verifying target database '$TARGET_DB' is fresh and contains no existing application schema objects..."

FRESHNESS_ERR_LOG="$(mktemp)"
set +e
EXISTING_APP_TABLES="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -A -c "
  SELECT count(*) FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name IN ('accounts', 'projects', 'tasks', 'flyway_schema_history');
" 2>"$FRESHNESS_ERR_LOG")"
FRESHNESS_QUERY_STATUS=$?
set -e

# Strip whitespace
EXISTING_APP_TABLES="$(echo "$EXISTING_APP_TABLES" | tr -d ' \r\n\t')"

if [[ "$FRESHNESS_QUERY_STATUS" -ne 0 ]]; then
  log_err "DATABASE FRESHNESS QUERY FAILURE: psql query failed with exit code $FRESHNESS_QUERY_STATUS!"
  cat "$FRESHNESS_ERR_LOG" >&2
  rm -f "$FRESHNESS_ERR_LOG"
  log_err "A failed query must never be interpreted as confirmation of an empty database."
  exit 1
fi
rm -f "$FRESHNESS_ERR_LOG"

# Validate that the result is a non-empty, non-negative integer
if [[ -z "$EXISTING_APP_TABLES" ]] || [[ ! "$EXISTING_APP_TABLES" =~ ^[0-9]+$ ]]; then
  log_err "DATABASE FRESHNESS QUERY CORRUPT: Expected non-negative integer from freshness query, received: '$EXISTING_APP_TABLES'!"
  exit 1
fi

# Reject any count other than exactly 0
if [[ "$EXISTING_APP_TABLES" -ne 0 ]]; then
  log_err "FRESH TARGET DATABASE REFUSAL: Target database '$TARGET_DB' already contains $EXISTING_APP_TABLES application table(s)!"
  log_err "Restoration requires a clean, empty destination database to prevent hybrid schema corruption."
  exit 1
fi
log_pass "Target database '$TARGET_DB' verified clean and empty (0 pre-existing application tables)."

# Step 7: Execute pg_restore with strict error handling (--exit-on-error, no error suppression)
log_info "Step 7: Executing pg_restore into database '$TARGET_DB'..."
RESTORE_ERR_LOG="$(mktemp)"
T_RESTORE_START="$(date +%s%N)"

set +e
PGPASSWORD="$DB_PASS" pg_restore \
  -h 127.0.0.1 \
  -p "$LOCAL_PORT" \
  -U "$DB_USER" \
  -d "$TARGET_DB" \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  "$BACKUP_FILE" >/dev/null 2>"$RESTORE_ERR_LOG"
RESTORE_STATUS=$?
set -e

T_RESTORE_END="$(date +%s%N)"
RESTORE_DURATION_MS=$(( (T_RESTORE_END - T_RESTORE_START) / 1000000 ))

if [[ "$RESTORE_STATUS" -ne 0 ]]; then
  log_err "CRITICAL RESTORATION FAILURE: pg_restore exited with non-zero exit code $RESTORE_STATUS!"
  log_err "pg_restore stderr output:"
  cat "$RESTORE_ERR_LOG" >&2
  rm -f "$RESTORE_ERR_LOG"
  exit 1
fi
rm -f "$RESTORE_ERR_LOG"
log_pass "pg_restore executed successfully in ${RESTORE_DURATION_MS} ms (exit code 0)."

# Step 8: Calculate Data Age / Measured RPO (clearly distinct from restore duration)
BACKUP_EPOCH="$(grep -o '"backup_epoch_seconds": [0-9]*' "$MANIFEST_FILE" | awk '{print $2}' || true)"
CURRENT_EPOCH="$(date -u +"%s")"
BACKUP_AGE_SECONDS=$(( CURRENT_EPOCH - BACKUP_EPOCH ))
log_info "Backup Age / Measured Recovery Point (RPO): ${BACKUP_AGE_SECONDS} seconds since backup creation."

# Step 9: Comprehensive Data Integrity & Schema Validation
log_info "Step 9: Executing comprehensive post-restore data integrity validation..."

# A: Flyway schema validation via genuine Flyway engine
log_info "Validating schema against authentic Flyway migrations..."
run_flyway_migration_runner "validate" "127.0.0.1" "$LOCAL_PORT" "$TARGET_DB" "$DB_USER" "$DB_PASS"

# Direct query of flyway_schema_history
MIGRATIONS_COUNT="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM flyway_schema_history WHERE success=true;" | xargs)"
log_info "Verified successful schema migrations: $MIGRATIONS_COUNT"
if [[ "$MIGRATIONS_COUNT" -lt 1 ]]; then
  log_err "INTEGRITY FAILURE: No successful Flyway migrations found in restored database!"
  exit 1
fi

FABRICATED_CHECKSUMS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM flyway_schema_history WHERE checksum = 12345678;" | xargs)"
if [[ "$FABRICATED_CHECKSUMS" -gt 0 ]]; then
  log_err "INTEGRITY FAILURE: Restored database contains fabricated checksum (12345678)!"
  exit 1
fi
log_pass "Flyway schema history verified genuine."

# B: Table row counts (strict error handling, zero error suppression)
ACCOUNTS_COUNT="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM accounts;" | xargs)"
PROJECTS_COUNT="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM projects;" | xargs)"
TASKS_COUNT="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks;" | xargs)"

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

# C: Relational foreign key integrity (strict error handling, zero error suppression)
ORPHAN_PROJECTS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM projects WHERE owner_id NOT IN (SELECT id FROM accounts);" | xargs)"
ORPHAN_TASKS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks WHERE project_id NOT IN (SELECT id FROM projects);" | xargs)"

if [[ "$ORPHAN_PROJECTS" -ne 0 ]]; then
  log_err "RELATIONAL INTEGRITY FAILURE: Found $ORPHAN_PROJECTS orphaned project(s)!"
  exit 1
fi
if [[ "$ORPHAN_TASKS" -ne 0 ]]; then
  log_err "RELATIONAL INTEGRITY FAILURE: Found $ORPHAN_TASKS orphaned task(s)!"
  exit 1
fi
log_pass "Relational integrity verified: 0 orphaned projects, 0 orphaned tasks."

# D: Task check constraint verification (strict error handling, zero error suppression)
INVALID_TASK_STATUSES="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT count(*) FROM tasks WHERE status NOT IN ('TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE');" | xargs)"
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
echo "Restore Time:      ${RESTORE_DURATION_MS} ms (pg_restore execution)"
echo "Backup Age (RPO):  ${BACKUP_AGE_SECONDS} seconds"
echo "Verified Records:  $ACCOUNTS_COUNT accounts, $PROJECTS_COUNT projects, $TASKS_COUNT tasks"
echo "Integrity Status:  All foreign keys, check constraints, and Flyway checksums 100% verified"
echo "======================================================================="
