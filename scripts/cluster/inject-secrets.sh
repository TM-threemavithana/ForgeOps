#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G06 — Out-of-Band Secret Injector
# Injects database credentials directly into Kubernetes namespaces out-of-band
# Uses file-based injection (--from-file) to prevent exposure in process arguments
# Enforces ADR-0006: Zero credentials committed to Git, logs, or process table
# ==============================================================================

set -euo pipefail

KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"
EXPECTED_CONTEXT="kind-forgeops"
SECRET_NAME="forgetasks-db-secret"
TARGET_NS="forgeops-dev"
OVERWRITE=false
CUSTOM_SECRET_FILE=""

VALIDATE_ONLY=false

# Parse Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n)
      TARGET_NS="$2"
      shift 2
      ;;
    --secret-file|-f)
      CUSTOM_SECRET_FILE="$2"
      shift 2
      ;;
    --overwrite)
      OVERWRITE=true
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    *)
      # Fallback to positional namespace argument if not a flag
      TARGET_NS="$1"
      shift
      ;;
  esac
done

if [ "${CONFIRM_SECRET_OVERWRITE:-no}" = "yes" ]; then
  OVERWRITE=true
fi

echo "=============================================================================="
echo " ForgeOps G06 — Out-of-Band Secret Injector"
echo " Target Namespace: ${TARGET_NS}"
echo " Secret Object:    ${SECRET_NAME}"
echo " Overwrite Mode:   ${OVERWRITE}"
echo " Validate Only:    ${VALIDATE_ONLY}"
echo "=============================================================================="

# 1. Kubeconfig and Context Verification (Skipped in validate-only mode)
if [ "$VALIDATE_ONLY" != true ]; then
  if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "[FAIL] Isolated kubeconfig '${KUBECONFIG_FILE}' not found." >&2
    echo "       Ensure cluster is running via: make cluster-create" >&2
    exit 1
  fi

  CURRENT_CTX=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" config current-context 2>/dev/null || true)
  if [ "$CURRENT_CTX" != "$EXPECTED_CONTEXT" ]; then
    echo "[FAIL] Kubeconfig context mismatch. Expected '${EXPECTED_CONTEXT}', found '${CURRENT_CTX}'." >&2
    exit 1
  fi

  # 2. Namespace Existence Check
  if ! kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get namespace "${TARGET_NS}" >/dev/null 2>&1; then
    echo "[FAIL] Target namespace '${TARGET_NS}' does not exist." >&2
    echo "       Apply namespaces first: kubectl apply -f platform/k8s/namespaces/" >&2
    exit 1
  fi
fi

# 3. Locate and Validate Protected Password File
# Approved native-WSL storage only; no implicit fallback to Windows /mnt/c mounts
APPROVED_SECRET_FILE="${HOME}/.config/forgeops/secrets/db_password.txt"
RESOLVED_FILE="${CUSTOM_SECRET_FILE:-$APPROVED_SECRET_FILE}"

# Explicitly reject paths residing on Windows mounts (/mnt/c, 9p filesystems)
case "$RESOLVED_FILE" in
  /mnt/*|*/mnt/*)
    echo "[FAIL] Refusing credential path under Windows mount: '${RESOLVED_FILE}'." >&2
    echo "       Credentials under /mnt/c or 9p/drvfs filesystems cannot enforce POSIX permissions (0600)." >&2
    echo "       Approved native-WSL storage: ${APPROVED_SECRET_FILE}" >&2
    exit 1
    ;;
esac

# Fail closed if approved credential file does not exist (zero automatic generation)
if [ ! -e "$RESOLVED_FILE" ]; then
  echo "[FAIL] Approved credential file '${RESOLVED_FILE}' does not exist." >&2
  echo "       Fail-closed: Out-of-band credential file must be provisioned in native WSL first." >&2
  exit 1
fi

# Require regular, non-symlink credential file
if [ -L "$RESOLVED_FILE" ]; then
  echo "[FAIL] Credential path '${RESOLVED_FILE}' is a symbolic link. Symlinks are forbidden for secrets." >&2
  exit 1
fi

if [ ! -f "$RESOLVED_FILE" ]; then
  echo "[FAIL] Credential path '${RESOLVED_FILE}' is not a regular file." >&2
  exit 1
fi

# Validate file ownership (must match current executing user UID)
CURRENT_UID=$(id -u)
FILE_UID=$(stat -c "%u" "$RESOLVED_FILE" 2>/dev/null || stat -f "%u" "$RESOLVED_FILE" 2>/dev/null || echo "")
if [ "$FILE_UID" != "$CURRENT_UID" ]; then
  echo "[FAIL] Credential file '${RESOLVED_FILE}' is owned by UID ${FILE_UID}, not current user UID ${CURRENT_UID}." >&2
  exit 1
fi

# Validate file permissions (must be mode 0600 or stricter, e.g. 0400; never auto-chmod untrusted paths)
FILE_PERMS=$(stat -c "%a" "$RESOLVED_FILE" 2>/dev/null || stat -f "%Lp" "$RESOLVED_FILE" 2>/dev/null || echo "000")
if [ "$FILE_PERMS" != "600" ] && [ "$FILE_PERMS" != "400" ]; then
  echo "[FAIL] Insecure file permissions (${FILE_PERMS}) on '${RESOLVED_FILE}'." >&2
  echo "       Permissions must be mode 0600 or stricter (e.g., 0400). Automatic chmod on untrusted paths is disabled." >&2
  exit 1
fi

# Validate protected parent directory (regular dir, non-symlink, owned by user, mode 0700 or stricter)
PARENT_DIR="$(dirname "$RESOLVED_FILE")"
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
if [ ! -s "$RESOLVED_FILE" ]; then
  echo "[FAIL] Secret file '${RESOLVED_FILE}' is empty. Aborting." >&2
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
done < "$RESOLVED_FILE"

if [ "$NUM_LINES" -eq 0 ]; then
  echo "[FAIL] Secret file '${RESOLVED_FILE}' is empty. Aborting." >&2
  exit 1
fi

if [ "$NUM_LINES" -gt 1 ]; then
  echo "[FAIL] Secret file '${RESOLVED_FILE}' contains multiple lines (${NUM_LINES} lines found)." >&2
  echo "       Password files must be single-line only. Refusing malformed secret." >&2
  exit 1
fi

# Strip trailing carriage return if present (Windows CRLF), preserving legitimate internal chars
SANITIZED_PASS="${FIRST_LINE%$'\r'}"

# Verify no internal newlines or carriage returns remain
if [[ "$SANITIZED_PASS" =~ [$'\r'$'\n'] ]]; then
  echo "[FAIL] Secret file '${RESOLVED_FILE}' contains embedded newline or carriage return characters." >&2
  echo "       Refusing malformed secret." >&2
  exit 1
fi

# Validate password length
if [ "${#SANITIZED_PASS}" -lt 8 ]; then
  echo "[FAIL] Password in '${RESOLVED_FILE}' is shorter than 8 characters. Refusing insecure credential." >&2
  exit 1
fi

echo "[1/2] Verified credential source: ${RESOLVED_FILE} (perms ${FILE_PERMS}, parent ${PARENT_PERMS}, single-line, valid length)"

# Exit early if only validating credential source
if [ "$VALIDATE_ONLY" = true ]; then
  unset FIRST_LINE
  unset SANITIZED_PASS
  echo "=============================================================================="
  echo " STATUS: CREDENTIAL SOURCE VALIDATED (Zero cluster mutations)"
  echo "=============================================================================="
  exit 0
fi

# 4. Check for Existing Secret & Enforce Overwrite Protection
SECRET_EXISTS=false
if kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get secret "${SECRET_NAME}" -n "${TARGET_NS}" >/dev/null 2>&1; then
  SECRET_EXISTS=true
fi

if [ "$SECRET_EXISTS" = true ] && [ "$OVERWRITE" != true ]; then
  echo "[INFO] Secret '${SECRET_NAME}' already exists in namespace '${TARGET_NS}'."
  echo "       Preserving existing Secret (immutable default)."
  echo "       To overwrite deliberately, run with: --overwrite or CONFIRM_SECRET_OVERWRITE=yes"
  echo "=============================================================================="
  echo " STATUS: PRESERVED (Existing Secret untouched)"
  echo "=============================================================================="
  unset FIRST_LINE
  unset SANITIZED_PASS
  exit 0
fi

# 5. Prepare Sanitized File for --from-file Injection
TMP_DIR=$(mktemp -d /tmp/forgeops-secret.XXXXXX)
chmod 0700 "$TMP_DIR"
TMP_PASS_FILE="${TMP_DIR}/postgres-password"

cleanup() {
  if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# Write exact password to temp file with zero trailing newline using bash builtin printf
printf "%s" "$SANITIZED_PASS" > "$TMP_PASS_FILE"
chmod 0600 "$TMP_PASS_FILE"

# Wipe password from shell memory immediately
unset FIRST_LINE
unset SANITIZED_PASS

# 6. Inject Secret via File Parameter (Zero Process Table /cmdline Exposure)
echo "[2/2] Injecting Secret '${SECRET_NAME}' via --from-file (zero process argument exposure)..."

kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" \
  create secret generic "${SECRET_NAME}" \
  --namespace="${TARGET_NS}" \
  --from-file="postgres-password=${TMP_PASS_FILE}" \
  --dry-run=client -o yaml | \
kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" apply -f - >/dev/null

echo "=============================================================================="
echo " STATUS: SECRET INJECTED SAFELY"
echo " Key:       postgres-password"
echo " Namespace: ${TARGET_NS}"
echo " Context:   ${EXPECTED_CONTEXT}"
echo " Security:  Zero CLI argument leakage; zero plaintext Secret files in Git."
echo "=============================================================================="
