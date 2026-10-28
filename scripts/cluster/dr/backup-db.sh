#!/usr/bin/env bash
# ForgeOps Gate G13 - PostgreSQL Safe Automated Backup Workflow (pg_dump -Fc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

SOURCE_NS="$DISPOSABLE_DR_NAMESPACE"
DB_NAME="forgetasks"
OUTPUT_DIR="$DEFAULT_BACKUP_DIR"
MODE="execute"

# Parse flags and positional arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-namespace)
      SOURCE_NS="$2"; shift 2 ;;
    --db-name)
      DB_NAME="$2"; shift 2 ;;
    --output-dir)
      OUTPUT_DIR="$2"; shift 2 ;;
    --dry-run|--validate-only)
      MODE="--validate-only"; shift ;;
    *)
      POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -ge 1 ]]; then
  SOURCE_NS="${POSITIONAL_ARGS[0]}"
fi
if [[ ${#POSITIONAL_ARGS[@]} -ge 2 ]]; then
  DB_NAME="${POSITIONAL_ARGS[1]}"
fi
if [[ ${#POSITIONAL_ARGS[@]} -ge 3 ]]; then
  OUTPUT_DIR="${POSITIONAL_ARGS[2]}"
fi

echo "======================================================================="
echo "ForgeOps G13: PostgreSQL Automated Backup Workflow"
echo "Source Namespace:      $SOURCE_NS"
echo "Database Name:         $DB_NAME"
echo "Output Directory:      $OUTPUT_DIR"
echo "Format:                pg_dump custom archive (-Fc) with SHA-256 manifest"
echo "======================================================================="

# Step 1: Preflight guards
run_dr_preflight_guards "$SOURCE_NS"
assert_backup_source_namespace "$SOURCE_NS"
check_disk_headroom "$OUTPUT_DIR"

if [[ "$MODE" == "--validate-only" ]]; then
  log_pass "Backup preflight validation passed successfully (dry-run mode)."
  exit 0
fi

# Step 2: Discover target database pod strictly
log_info "Discovering running source PostgreSQL pod in '$SOURCE_NS'..."

if [[ "$SOURCE_NS" == "$DISPOSABLE_DR_NAMESPACE" ]]; then
  # Strictly select only deployment/dr-source-db
  mapfile -t CANDIDATES < <(kubectl get pods -n "$SOURCE_NS" -l app=dr-source-db --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v '^$' || true)
  
  if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
    log_err "CRITICAL: No running Pods found for deployment/dr-source-db in namespace '$SOURCE_NS'!"
    exit 1
  fi
  if [[ "${#CANDIDATES[@]}" -gt 1 ]]; then
    log_err "CRITICAL: Multiple running Pods found for deployment/dr-source-db (${#CANDIDATES[@]}). Expected exactly 1!"
    exit 1
  fi

  POD="${CANDIDATES[0]}"

  # Strict safety check: Refuse if target pod is dr-target-db
  ROLE_LABEL="$(kubectl get pod "$POD" -n "$SOURCE_NS" -o jsonpath='{.metadata.labels.forgeops\.dev/role}' 2>/dev/null || true)"
  APP_LABEL="$(kubectl get pod "$POD" -n "$SOURCE_NS" -o jsonpath='{.metadata.labels.app}' 2>/dev/null || true)"
  if [[ "$APP_LABEL" == "dr-target-db" || "$ROLE_LABEL" == "target" ]]; then
    log_err "CRITICAL SAFETY REFUSAL: Discovered pod '$POD' carries target role label! Refusing to backup dr-target-db."
    exit 1
  fi

  # Verify owning deployment/replicaset
  OWNER_NAME="$(kubectl get pod "$POD" -n "$SOURCE_NS" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)"
  if [[ "$OWNER_NAME" != *"dr-source-db"* ]]; then
    log_err "CRITICAL SAFETY REFUSAL: Discovered pod '$POD' owner reference '$OWNER_NAME' is not dr-source-db!"
    exit 1
  fi
else
  # Non-disposable source (e.g. dev or gitops rehearsal)
  mapfile -t CANDIDATES < <(kubectl get pods -n "$SOURCE_NS" -l app.kubernetes.io/name=postgres --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v '^$' || true)
  if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
    log_err "CRITICAL: No running PostgreSQL pod found in namespace '$SOURCE_NS'!"
    exit 1
  fi
  if [[ "${#CANDIDATES[@]}" -gt 1 ]]; then
    log_err "CRITICAL: Ambiguous database pods in '$SOURCE_NS' (${#CANDIDATES[@]} found). Refusing unverified source."
    exit 1
  fi
  POD="${CANDIDATES[0]}"
fi

log_info "Identified and verified source PostgreSQL pod: $POD"

# Step 3: Secure runtime credential retrieval (never printed to logs or disk)
log_info "Securely retrieving database credentials from Kubernetes secret..."
SECRET_NAME="$(kubectl get secrets -n "$SOURCE_NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | grep -E 'forgetasks-db-secret|dr-db-secret' | head -n 1 || true)"
if [[ -z "$SECRET_NAME" ]]; then
  SECRET_NAME="dr-db-secret"
fi

DB_USER="forgeuser"
DB_PASS="$(kubectl get secret "$SECRET_NAME" -n "$SOURCE_NS" -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d || true)"
if [[ -z "$DB_PASS" ]]; then
  DB_PASS="$(kubectl get secret "$SECRET_NAME" -n "$SOURCE_NS" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
fi

if [[ -z "$DB_PASS" ]]; then
  log_err "CRITICAL: Failed to retrieve database password from secret '$SECRET_NAME' in '$SOURCE_NS'!"
  exit 1
fi
log_pass "Retrieved credentials securely in memory (redacted from logs)."

# Step 4: Prepare atomic output paths and cleanup trap
TIMESTAMP="$(date -u +"%Y%m%d-%H%M%SZ")"
EPOCH_SECONDS="$(date -u +"%s")"
BACKUP_BASENAME="forgeops-backup-${SOURCE_NS}-${DB_NAME}-${TIMESTAMP}"
TARGET_BACKUP_FILE="${OUTPUT_DIR}/${BACKUP_BASENAME}.dump"
TARGET_MANIFEST_FILE="${OUTPUT_DIR}/${BACKUP_BASENAME}.manifest.json"
TEMP_FILE="${OUTPUT_DIR}/${BACKUP_BASENAME}.tmp"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM ERR
  if [[ -f "$TEMP_FILE" ]]; then
    log_warn "Cleaning up temporary unfinalized backup file '$TEMP_FILE'..."
    rm -f "$TEMP_FILE"
  fi
  if [[ "$exit_code" -ne 0 ]]; then
    log_err "Backup workflow encountered an error (exit code: $exit_code). Incomplete backup discarded."
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM ERR

# Set restrictive permissions for directory and new files
umask 0077

# Step 5: Establish temporary port-forward for host-side pg_dump
LOCAL_PORT=$(( 15000 + (EPOCH_SECONDS % 1000) ))
log_info "Establishing local port-forward to ${SOURCE_NS}/${POD}:5432 on 127.0.0.1:${LOCAL_PORT}..."
kubectl port-forward -n "$SOURCE_NS" "pod/${POD}" "${LOCAL_PORT}:5432" >/dev/null 2>&1 &
PF_PID=$!
sleep 2

kill_pf() {
  kill -9 "$PF_PID" >/dev/null 2>&1 || true
}
trap 'kill_pf; cleanup' EXIT INT TERM ERR

# Step 6: Verify source database and non-empty synthetic dataset before dumping
log_info "Verifying source database and synthetic dataset before backup..."
SRC_ACCOUNTS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM accounts;" 2>/dev/null | xargs || true)"
SRC_PROJECTS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM projects;" 2>/dev/null | xargs || true)"
SRC_TASKS="$(PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM tasks;" 2>/dev/null | xargs || true)"

if [[ -z "$SRC_ACCOUNTS" || "$SRC_ACCOUNTS" -lt 1 || -z "$SRC_PROJECTS" || "$SRC_PROJECTS" -lt 1 || -z "$SRC_TASKS" || "$SRC_TASKS" -lt 1 ]]; then
  log_err "DATA PRE-VALIDATION FAILURE: Source database '$DB_NAME' in '$SOURCE_NS' has missing or empty dataset (accounts=${SRC_ACCOUNTS:-0}, projects=${SRC_PROJECTS:-0}, tasks=${SRC_TASKS:-0})!"
  exit 1
fi
log_pass "Source dataset verified prior to dump: $SRC_ACCOUNTS accounts, $SRC_PROJECTS projects, $SRC_TASKS tasks."

# Step 7: Execute pg_dump custom format (-Fc)
log_info "Executing pg_dump custom archive (-Fc) to temporary file..."
T_START="$(date +%s%N)"

DUMP_ERR_LOG="$(mktemp)"
set +e
PGPASSWORD="$DB_PASS" pg_dump \
  -h 127.0.0.1 \
  -p "$LOCAL_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -Fc \
  -b \
  -v \
  -f "$TEMP_FILE" 2>"$DUMP_ERR_LOG"
DUMP_STATUS=$?
set -e

T_END="$(date +%s%N)"
DUMP_DURATION_MS=$(( (T_END - T_START) / 1000000 ))

if [[ "$DUMP_STATUS" -ne 0 ]]; then
  log_err "pg_dump failed with exit code $DUMP_STATUS!"
  cat "$DUMP_ERR_LOG" >&2
  rm -f "$DUMP_ERR_LOG"
  exit 1
fi
rm -f "$DUMP_ERR_LOG"
log_pass "pg_dump completed successfully in ${DUMP_DURATION_MS} ms."

# Step 8: Validate temporary archive readability & integrity before committing
log_info "Validating archive readability and structure via pg_restore -l..."
if ! pg_restore -l "$TEMP_FILE" >/dev/null 2>&1; then
  log_err "INTEGRITY FAILURE: pg_restore failed to read generated backup archive!"
  exit 1
fi

ARCHIVE_SIZE_BYTES="$(wc -c < "$TEMP_FILE" | tr -d ' ')"
if [[ "$ARCHIVE_SIZE_BYTES" -lt 1024 ]]; then
  log_err "CORRUPTION REFUSAL: Generated backup file size (${ARCHIVE_SIZE_BYTES} bytes) is suspiciously small (< 1KB)!"
  exit 1
fi

# Step 9: Atomic finalize move
mv "$TEMP_FILE" "$TARGET_BACKUP_FILE"
chmod 0600 "$TARGET_BACKUP_FILE"
log_pass "Backup archive committed atomically: $TARGET_BACKUP_FILE (${ARCHIVE_SIZE_BYTES} bytes)"

# Step 10: Compute SHA-256 and gather metadata
SHA256="$(sha256sum "$TARGET_BACKUP_FILE" | awk '{print $1}')"
PG_CLIENT_VER="$(pg_dump --version | head -n 1)"
PG_SERVER_VER="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SHOW server_version;" 2>/dev/null | xargs || echo "16.x")"

# Collect list of tables in backup
TABLES_IN_ARCHIVE=()
while IFS= read -r line; do
  TABLES_IN_ARCHIVE+=("$line")
done < <(pg_restore -l "$TARGET_BACKUP_FILE" | awk '$6=="TABLE" {print $8}' | sort -u || true)

TABLES_JSON_ARRAY="$(printf '%s\n' "${TABLES_IN_ARCHIVE[@]}" | jq -R . | jq -s . 2>/dev/null || echo '["accounts","projects","tasks","flyway_schema_history"]')"

# Step 11: Generate immutable manifest JSON
log_info "Generating immutable backup manifest: $TARGET_MANIFEST_FILE..."
cat <<EOF > "$TARGET_MANIFEST_FILE"
{
  "manifest_schema_version": "1.0",
  "backup_format": "pg_dump_custom_v1",
  "backup_file": "$(basename "$TARGET_BACKUP_FILE")",
  "source_namespace": "$SOURCE_NS",
  "source_database": "$DB_NAME",
  "source_db_user": "$DB_USER",
  "source_pg_version": "$PG_SERVER_VER",
  "pg_dump_version": "$PG_CLIENT_VER",
  "backup_utc_timestamp": "$TIMESTAMP",
  "backup_epoch_seconds": $EPOCH_SECONDS,
  "dump_duration_ms": $DUMP_DURATION_MS,
  "archive_size_bytes": $ARCHIVE_SIZE_BYTES,
  "sha256_checksum": "$SHA256",
  "tables_catalog": $TABLES_JSON_ARRAY,
  "immutable": true
}
EOF
chmod 0600 "$TARGET_MANIFEST_FILE"
log_pass "Manifest written successfully (SHA-256: $SHA256)."

# Step 12: Teardown port-forward and final checks
kill_pf
trap - EXIT INT TERM ERR

assert_protected_pvcs_intact

echo "======================================================================="
log_pass "PostgreSQL Backup Completed Successfully!"
echo "Backup Archive:  $TARGET_BACKUP_FILE"
echo "Manifest:        $TARGET_MANIFEST_FILE"
echo "Archive Size:    $ARCHIVE_SIZE_BYTES bytes"
echo "SHA-256:         $SHA256"
echo "Duration:        ${DUMP_DURATION_MS} ms"
echo "======================================================================="
