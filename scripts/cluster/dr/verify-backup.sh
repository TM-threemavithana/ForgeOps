#!/usr/bin/env bash
# ForgeOps Gate G13 - PostgreSQL Backup Archive & Manifest Verification Utility
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-dr.sh"

INPUT_PATH="${1:-}"

if [[ -z "$INPUT_PATH" ]]; then
  echo "Usage: $0 <path-to-backup.dump-or-manifest.json>"
  exit 1
fi

echo "======================================================================="
echo "ForgeOps G13: PostgreSQL Backup Archive Integrity Verification"
echo "Target Input: $INPUT_PATH"
echo "======================================================================="

# Determine backup file and manifest file paths
if [[ "$INPUT_PATH" == *.manifest.json ]]; then
  MANIFEST_FILE="$INPUT_PATH"
  BACKUP_FILE="${INPUT_PATH%.manifest.json}.dump"
elif [[ "$INPUT_PATH" == *.dump ]]; then
  BACKUP_FILE="$INPUT_PATH"
  MANIFEST_FILE="${INPUT_PATH%.dump}.manifest.json"
else
  # Check if both exist with extension
  if [[ -f "${INPUT_PATH}.dump" ]]; then
    BACKUP_FILE="${INPUT_PATH}.dump"
    MANIFEST_FILE="${INPUT_PATH}.manifest.json"
  else
    log_err "Unrecognized file format: '$INPUT_PATH' (expected .dump or .manifest.json)"
    exit 1
  fi
fi

# Step 1: Verify files exist
log_info "Verifying existence of archive and manifest files..."
if [[ ! -f "$BACKUP_FILE" ]]; then
  log_err "CRITICAL: Backup archive file '$BACKUP_FILE' not found!"
  exit 1
fi
if [[ ! -f "$MANIFEST_FILE" ]]; then
  log_err "CRITICAL: Manifest file '$MANIFEST_FILE' not found!"
  exit 1
fi
log_pass "Both archive and manifest files located."

# Step 2: Read and parse manifest
log_info "Reading manifest metadata..."
EXPECTED_SHA256="$(grep -o '"sha256_checksum": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4 || true)"
EXPECTED_SIZE="$(grep -o '"archive_size_bytes": [0-9]*' "$MANIFEST_FILE" | awk '{print $2}' || true)"
SOURCE_NS="$(grep -o '"source_namespace": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4 || true)"
SOURCE_DB="$(grep -o '"source_database": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4 || true)"
TIMESTAMP="$(grep -o '"backup_utc_timestamp": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4 || true)"

if [[ -z "$EXPECTED_SHA256" || -z "$EXPECTED_SIZE" ]]; then
  log_err "CORRUPTION REFUSAL: Manifest file is malformed or missing required integrity fields!"
  exit 1
fi

log_info "Manifest metadata: Source=${SOURCE_NS}/${SOURCE_DB}, Timestamp=${TIMESTAMP}, Declared Size=${EXPECTED_SIZE} bytes"

# Step 3: Verify file size
ACTUAL_SIZE="$(wc -c < "$BACKUP_FILE" | tr -d ' ')"
if [[ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]]; then
  log_err "SIZE MISMATCH: Declared size ${EXPECTED_SIZE} != actual size ${ACTUAL_SIZE} bytes!"
  exit 1
fi
log_pass "Archive file size verified: ${ACTUAL_SIZE} bytes."

# Step 4: Cryptographic SHA-256 Checksum Validation
log_info "Computing cryptographic SHA-256 hash of '$BACKUP_FILE'..."
ACTUAL_SHA256="$(sha256sum "$BACKUP_FILE" | awk '{print $1}')"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  log_err "CHECKSUM CORRUPTION DETECTED!"
  log_err "Expected SHA-256: $EXPECTED_SHA256"
  log_err "Computed SHA-256: $ACTUAL_SHA256"
  exit 1
fi
log_pass "SHA-256 checksum matched declared manifest: $ACTUAL_SHA256"

# Step 5: Verify archive magic header (pg_dump custom format)
MAGIC_HEADER="$(head -c 5 "$BACKUP_FILE" 2>/dev/null || true)"
if [[ "$MAGIC_HEADER" != "PGDMP" ]]; then
  log_err "INVALID FORMAT: File header '$MAGIC_HEADER' does not match pg_dump custom format 'PGDMP'!"
  exit 1
fi
log_pass "Archive magic header verified ('PGDMP')."

# Step 6: Verify Table of Contents (TOC) via pg_restore -l
log_info "Inspecting archive Table of Contents (TOC) via pg_restore..."
if ! pg_restore -l "$BACKUP_FILE" >/dev/null 2>&1; then
  log_err "INTEGRITY FAILURE: pg_restore failed to parse archive TOC!"
  exit 1
fi

# Verify required core tables
MANDATORY_TABLES=("accounts" "projects" "tasks" "flyway_schema_history")
TOC_OUTPUT="$(pg_restore -l "$BACKUP_FILE")"

MISSING_TABLES=0
for tbl in "${MANDATORY_TABLES[@]}"; do
  if echo "$TOC_OUTPUT" | grep -qE "TABLE .* ${tbl}"; then
    log_pass "Verified table present in TOC: $tbl"
  else
    log_err "MISSING TABLE IN ARCHIVE: Required table '$tbl' is absent from backup!"
    MISSING_TABLES=1
  fi
done

if [[ "$MISSING_TABLES" -ne 0 ]]; then
  log_err "INTEGRITY REFUSAL: One or more mandatory tables missing from backup archive!"
  exit 1
fi

# Step 7: Architectural tool verification note
log_info "Note: pg_verifybackup is deliberately NOT invoked because it is designed"
log_info "      strictly for physical pg_basebackup directories, whereas pg_dump"
log_info "      custom archives are verified via SHA-256 and pg_restore TOC catalog."

echo "======================================================================="
log_pass "Backup Archive & Manifest Integrity Verified Successfully!"
echo "Archive File:     $BACKUP_FILE"
echo "Source:           $SOURCE_NS / $SOURCE_DB"
echo "UTC Timestamp:    $TIMESTAMP"
echo "Archive Size:     $ACTUAL_SIZE bytes"
echo "SHA-256:          $ACTUAL_SHA256"
echo "Tables Verified:  ${MANDATORY_TABLES[*]}"
echo "======================================================================="
