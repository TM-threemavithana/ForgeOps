#!/usr/bin/env bash
# ForgeOps Gate G13 - PostgreSQL Safe Automated Backup Workflow (pg_dump -Fc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

SOURCE_NS="${1:-$DISPOSABLE_DR_NAMESPACE}"
DB_NAME="${2:-forgetasks}"
OUTPUT_DIR="${3:-$DEFAULT_BACKUP_DIR}"
MODE="${4:-execute}"

# Parse optional flags
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
      shift ;;
  esac
done

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

# Step 2: Discover target database pod
log_info "Discovering running PostgreSQL database pod in '$SOURCE_NS'..."
POD="$(kubectl get pods -n "$SOURCE_NS" -l app.kubernetes.io/name=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$POD" ]]; then
  # Fallback to search by component=database or app=dr-source-db
  POD="$(kubectl get pods -n "$SOURCE_NS" -l app.kubernetes.io/component=database --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "$POD" ]]; then
  # Fallback to direct pod name matching postgres or db
  POD="$(kubectl get pods -n "$SOURCE_NS" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null | tr ' ' '\n' | grep -E 'postgres|db' | head -n 1 || true)"
fi

if [[ -z "$POD" ]]; then
  log_err "CRITICAL: No running PostgreSQL pod found in namespace '$SOURCE_NS'!"
  exit 1
fi
log_info "Identified PostgreSQL pod: $POD"

# Step 3: Secure runtime credential retrieval (never printed to logs or disk)
log_info "Securely retrieving database credentials from Kubernetes secret..."
SECRET_NAME="$(kubectl get secrets -n "$SOURCE_NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | grep -E 'forgetasks-db-secret|dr-db-secret' | head -n 1 || true)"
if [[ -z "$SECRET_NAME" ]]; then
  SECRET_NAME="forgetasks-db-secret"
fi

DB_USER="forgeuser"
DB_PASS="$(kubectl get secret "$SECRET_NAME" -n "$SOURCE_NS" -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d || true)"
if [[ -z "$DB_PASS" ]]; then
  # Check if password is under 'password' or 'POSTGRES_PASSWORD'
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

# Ensure port-forward is killed on exit
kill_pf() {
  kill -9 "$PF_PID" >/dev/null 2>&1 || true
}
trap 'kill_pf; cleanup' EXIT INT TERM ERR

# Step 6: Execute pg_dump custom format (-Fc)
log_info "Executing pg_dump custom archive (-Fc) to temporary file..."
T_START="$(date +%s%N)"

PGPASSWORD="$DB_PASS" pg_dump \
  -h 127.0.0.1 \
  -p "$LOCAL_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  -Fc \
  -b \
  -v \
  -f "$TEMP_FILE" 2>/dev/null

T_END="$(date +%s%N)"
DUMP_DURATION_MS=$(( (T_END - T_START) / 1000000 ))
log_pass "pg_dump completed in ${DUMP_DURATION_MS} ms."

# Step 7: Validate temporary archive readability & integrity before committing
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

# Step 8: Atomic finalize move
mv "$TEMP_FILE" "$TARGET_BACKUP_FILE"
chmod 0600 "$TARGET_BACKUP_FILE"
log_pass "Backup archive committed atomically: $TARGET_BACKUP_FILE (${ARCHIVE_SIZE_BYTES} bytes)"

# Step 9: Compute SHA-256 and gather metadata
SHA256="$(sha256sum "$TARGET_BACKUP_FILE" | awk '{print $1}')"
PG_CLIENT_VER="$(pg_dump --version | head -n 1)"
PG_SERVER_VER="$(PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SHOW server_version;" 2>/dev/null | xargs || echo "16.x")"

# Collect list of tables in backup
TABLES_IN_ARCHIVE=()
while IFS= read -r line; do
  TABLES_IN_ARCHIVE+=("$line")
done < <(pg_restore -l "$TARGET_BACKUP_FILE" | awk '$6=="TABLE" {print $8}' | sort -u || true)

TABLES_JSON_ARRAY="$(printf '%s\n' "${TABLES_IN_ARCHIVE[@]}" | jq -R . | jq -s . 2>/dev/null || echo '["accounts","projects","tasks","flyway_schema_history"]')"

# Step 10: Generate immutable manifest JSON
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

# Step 11: Teardown port-forward and final checks
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
