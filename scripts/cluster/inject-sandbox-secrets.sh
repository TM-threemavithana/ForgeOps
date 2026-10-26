#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G07 — Guarded Sandbox Secret Provisioning Script (Hardened)
# Injects database credentials exclusively into 'forgeops-helm-sandbox'
# Uses atomic create-only file-based injection (--from-file)
#
# Hardened Security Boundaries:
# 1. Fixed Credential Source: Strictly locked to ~/.config/forgeops/secrets/sandbox_db_password.txt
#    No CLI override allowed; explicitly rejects G06 database credential files.
# 2. Fixed Target Boundary: Strictly targets namespace 'forgeops-helm-sandbox' and context 'kind-forgeops'.
# 3. Native WSL Hygiene: Rejects Windows /mnt mounts and symbolic links; enforces mode 0600 (file) and 0700 (parent).
# 4. Strict Umask & Scoped Cleanup: Sets umask 077 before mktemp; cleanup removes only script-owned temp directory.
# 5. Atomic Create-Only: Uses direct 'kubectl create secret generic' (zero overwrite, zero rotation).
# 6. Process Hygiene: Zero password exposure in CLI arguments, process tables (/proc), or logs.
# 7. Operator Authorization: Requires explicit '--confirm' or 'CONFIRM_SANDBOX_INJECT=yes'.
# 8. Dry-Run Verification: Provides '--validate-only' performing zero cluster mutations.
# ==============================================================================

set -euo pipefail

KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"
EXPECTED_CONTEXT="kind-forgeops"
SECRET_NAME="forgetasks-db-secret"
TARGET_NS="forgeops-helm-sandbox"

# Credential loading is strictly hardcoded to the sandbox password file
APPROVED_SECRET_FILE="${HOME}/.config/forgeops/secrets/sandbox_db_password.txt"
G06_SECRET_FILE="${HOME}/.config/forgeops/secrets/db_password.txt"

VALIDATE_ONLY=false
CONFIRMED=false
TMP_DIR=""

# Scoped cleanup function ensuring removal of only script-created temporary directory
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    case "$TMP_DIR" in
      /tmp/forgeops-sandbox-secret.*)
        rm -rf "$TMP_DIR"
        ;;
    esac
  fi
}
trap cleanup EXIT INT TERM HUP

# Parse Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRMED=true
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    --secret-file*|-f*)
      echo "ERROR: CLI credential override is strictly forbidden." >&2
      echo "       Sandbox secret injection is locked exclusively to:" >&2
      echo "       ${APPROVED_SECRET_FILE}" >&2
      exit 1
      ;;
    --overwrite*)
      echo "ERROR: Overwrite flag is strictly forbidden." >&2
      echo "       Sandbox secret injection operates in atomic create-only mode." >&2
      echo "       Existing database credentials must not be rotated or overwritten." >&2
      exit 1
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Guarded atomic secret provisioner for ForgeOps Helm Sandbox."
      echo "Credential source is hardcoded to: ${APPROVED_SECRET_FILE}"
      echo "Target namespace is hardcoded to:  ${TARGET_NS}"
      echo ""
      echo "Options:"
      echo "  --validate-only     Verify credential file, permissions, and context with zero mutations"
      echo "  --confirm           Acknowledge operator authorization to inject secret into sandbox"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Run with --help for usage instructions." >&2
      exit 1
      ;;
  esac
done

if [ "${CONFIRM_SANDBOX_INJECT:-no}" = "yes" ]; then
  CONFIRMED=true
fi

echo "=============================================================================="
echo " ForgeOps G07 — Guarded Sandbox Secret Provisioner (Atomic Create-Only)"
echo " Target Namespace: ${TARGET_NS} (Fixed boundary)"
echo " Context:          ${EXPECTED_CONTEXT} (Fixed boundary)"
echo " Secret Object:    ${SECRET_NAME} (Key: postgres-password)"
echo " Credential File:  ${APPROVED_SECRET_FILE} (Locked)"
echo " Validate Only:    ${VALIDATE_ONLY}"
echo " Confirmed:        ${CONFIRMED}"
echo "=============================================================================="

# 1. Kubeconfig and Context Verification
if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "[FAIL] Isolated kubeconfig '${KUBECONFIG_FILE}' not found." >&2
  echo "       Ensure Kind cluster is running: make cluster-status" >&2
  exit 1
fi

CURRENT_CTX=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" config current-context 2>/dev/null || true)
if [ "$CURRENT_CTX" != "$EXPECTED_CONTEXT" ]; then
  echo "[FAIL] Kubeconfig context mismatch. Expected '${EXPECTED_CONTEXT}', found '${CURRENT_CTX}'." >&2
  exit 1
fi

# 2. Check Sandbox Namespace Existence
NS_EXISTS=false
if kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get namespace "${TARGET_NS}" >/dev/null 2>&1; then
  NS_EXISTS=true
fi

if [ "$VALIDATE_ONLY" != true ] && [ "$NS_EXISTS" != true ]; then
  echo "[FAIL] Target sandbox namespace '${TARGET_NS}' does not exist." >&2
  echo "       Create the sandbox namespace first: kubectl create namespace ${TARGET_NS}" >&2
  exit 1
fi

# 3. Validate Dedicated Sandbox Credential Source
# Explicitly reject paths residing on Windows mounts (/mnt/c, 9p filesystems)
case "$APPROVED_SECRET_FILE" in
  /mnt/*|*/mnt/*)
    echo "[FAIL] Refusing credential path under Windows mount: '${APPROVED_SECRET_FILE}'." >&2
    echo "       Credentials under /mnt/c or 9p/drvfs filesystems cannot enforce POSIX permissions (0600)." >&2
    exit 1
    ;;
esac

# Explicitly reject if attempting to reference G06 database password file
if [ "$APPROVED_SECRET_FILE" = "$G06_SECRET_FILE" ]; then
  echo "[FAIL] Refusing G06 database password file for sandbox injection." >&2
  echo "       Sandbox must use an independent credential file." >&2
  exit 1
fi

# Fail closed if approved credential file does not exist
if [ ! -e "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Dedicated sandbox credential file '${APPROVED_SECRET_FILE}' does not exist." >&2
  echo "       Fail-closed: Sandbox credential file must be provisioned in native WSL first." >&2
  echo "       Example: head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16 > ${APPROVED_SECRET_FILE} && chmod 0600 ${APPROVED_SECRET_FILE}" >&2
  exit 1
fi

# Require regular, non-symlink credential file
if [ -L "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Credential path '${APPROVED_SECRET_FILE}' is a symbolic link. Symlinks are forbidden for secrets." >&2
  exit 1
fi

if [ ! -f "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Credential path '${APPROVED_SECRET_FILE}' is not a regular file." >&2
  exit 1
fi

# Validate file ownership (must match current executing user UID)
CURRENT_UID=$(id -u)
FILE_UID=$(stat -c "%u" "$APPROVED_SECRET_FILE" 2>/dev/null || stat -f "%u" "$APPROVED_SECRET_FILE" 2>/dev/null || echo "")
if [ "$FILE_UID" != "$CURRENT_UID" ]; then
  echo "[FAIL] Credential file '${APPROVED_SECRET_FILE}' is owned by UID ${FILE_UID}, not current user UID ${CURRENT_UID}." >&2
  exit 1
fi

# Validate file permissions (must be mode 0600 or stricter, e.g. 0400)
FILE_PERMS=$(stat -c "%a" "$APPROVED_SECRET_FILE" 2>/dev/null || stat -f "%Lp" "$APPROVED_SECRET_FILE" 2>/dev/null || echo "000")
if [ "$FILE_PERMS" != "600" ] && [ "$FILE_PERMS" != "400" ]; then
  echo "[FAIL] Insecure file permissions (${FILE_PERMS}) on '${APPROVED_SECRET_FILE}'." >&2
  echo "       Permissions must be mode 0600 or stricter (e.g., 0400)." >&2
  exit 1
fi

# Validate protected parent directory (regular dir, non-symlink, owned by user, mode 0700 or stricter)
PARENT_DIR="$(dirname "$APPROVED_SECRET_FILE")"
if [ -L "$PARENT_DIR" ]; then
  echo "[FAIL] Credential parent directory '${PARENT_DIR}' is a symbolic link." >&2
  exit 1
fi

if [ ! -d "$PARENT_DIR" ]; then
  echo "[FAIL] Credential parent directory '${PARENT_DIR}' does not exist or is not a directory." >&2
  exit 1
fi

PARENT_UID=$(stat -c "%u" "$PARENT_DIR" 2>/dev/null || stat -f "%u" "$PARENT_DIR" 2>/dev/null || echo "")
if [ "$PARENT_UID" != "$CURRENT_UID" ]; then
  echo "[FAIL] Credential parent directory '${PARENT_DIR}' is owned by UID ${PARENT_UID}, not current user UID ${CURRENT_UID}." >&2
  exit 1
fi

PARENT_PERMS=$(stat -c "%a" "$PARENT_DIR" 2>/dev/null || stat -f "%Lp" "$PARENT_DIR" 2>/dev/null || echo "000")
if [ "$PARENT_PERMS" != "700" ] && [ "$PARENT_PERMS" != "500" ]; then
  echo "[FAIL] Insecure parent directory permissions (${PARENT_PERMS}) on '${PARENT_DIR}'." >&2
  echo "       Parent directory must be mode 0700 or stricter (e.g., 0500)." >&2
  exit 1
fi

# Check that file is non-empty
if [ ! -s "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' is empty. Aborting." >&2
  exit 1
fi

# Validate single-line structure: reject malformed multi-line files
NUM_LINES=0
FIRST_LINE=""
while IFS= read -r line || [ -n "$line" ]; do
  NUM_LINES=$((NUM_LINES + 1))
  if [ "$NUM_LINES" -eq 1 ]; then
    FIRST_LINE="$line"
  fi
done < "$APPROVED_SECRET_FILE"

if [ "$NUM_LINES" -eq 0 ]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' is empty. Aborting." >&2
  exit 1
fi

if [ "$NUM_LINES" -gt 1 ]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' contains multiple lines (${NUM_LINES} lines found)." >&2
  echo "       Password files must be single-line only. Refusing malformed secret." >&2
  exit 1
fi

# Strip trailing carriage return if present (Windows CRLF)
SANITIZED_PASS="${FIRST_LINE%$'\r'}"

# Verify no internal newlines or carriage returns remain
if [[ "$SANITIZED_PASS" =~ [$'\r'$'\n'] ]]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' contains embedded newline or carriage return characters." >&2
  echo "       Refusing malformed secret." >&2
  exit 1
fi

# Validate password length
if [ "${#SANITIZED_PASS}" -lt 8 ]; then
  echo "[FAIL] Password in '${APPROVED_SECRET_FILE}' is shorter than 8 characters. Refusing insecure credential." >&2
  exit 1
fi

echo "[1/2] Verified sandbox credential source: ${APPROVED_SECRET_FILE} (perms ${FILE_PERMS}, parent ${PARENT_PERMS}, single-line, valid length)"

# Exit early if only validating credential source
if [ "$VALIDATE_ONLY" = true ]; then
  unset FIRST_LINE
  unset SANITIZED_PASS
  echo "=============================================================================="
  echo " STATUS: CREDENTIAL SOURCE VALIDATED (Zero cluster mutations)"
  echo " Target: ${TARGET_NS} (Namespace exists: ${NS_EXISTS})"
  echo " Mode:   Atomic create-only ready"
  echo "=============================================================================="
  exit 0
fi

# 4. Require Explicit Operator Confirmation
if [ "$CONFIRMED" != true ]; then
  echo "[FAIL] Sandbox secret injection requires explicit operator confirmation." >&2
  echo "       Re-run with '--confirm' or 'CONFIRM_SANDBOX_INJECT=yes'." >&2
  unset FIRST_LINE
  unset SANITIZED_PASS
  exit 1
fi

# 5. Check for Existing Secret & Enforce Atomic Create-Only Policy
if kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get secret "${SECRET_NAME}" -n "${TARGET_NS}" >/dev/null 2>&1; then
  echo "[FAIL] Secret '${SECRET_NAME}' already exists in namespace '${TARGET_NS}'." >&2
  echo "       Atomic create-only policy: Refusing to modify, rotate, or overwrite existing Secret." >&2
  echo "       To maintain credential integrity, existing database credentials must not be rotated." >&2
  unset FIRST_LINE
  unset SANITIZED_PASS
  exit 1
fi

# 6. Prepare Sanitized File for --from-file Injection with Restrictive Umask
OLD_UMASK=$(umask)
umask 077

TMP_DIR=$(mktemp -d /tmp/forgeops-sandbox-secret.XXXXXX)
chmod 0700 "$TMP_DIR"
TMP_PASS_FILE="${TMP_DIR}/postgres-password"

# Write exact password to temp file with zero trailing newline
printf "%s" "$SANITIZED_PASS" > "$TMP_PASS_FILE"
chmod 0600 "$TMP_PASS_FILE"
umask "$OLD_UMASK"

# Wipe password from shell memory immediately
unset FIRST_LINE
unset SANITIZED_PASS

# 7. Atomic Create-Only Secret Provisioning (Zero CLI Argument / Process Table Leakage)
echo "[2/2] Provisioning Secret '${SECRET_NAME}' into '${TARGET_NS}' (atomic create-only)..."

kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" \
  create secret generic "${SECRET_NAME}" \
  --namespace="${TARGET_NS}" \
  --from-file="postgres-password=${TMP_PASS_FILE}" >/dev/null

echo "=============================================================================="
echo " STATUS: SANDBOX SECRET INJECTED SAFELY (Atomic Create-Only)"
echo " Key:       postgres-password"
echo " Namespace: ${TARGET_NS}"
echo " Context:   ${EXPECTED_CONTEXT}"
echo " Security:  Zero CLI argument leakage; zero plaintext Secret files in Git."
echo " Policy:    Atomic create-only; script refuses to rotate or overwrite existing credentials."
echo "=============================================================================="
