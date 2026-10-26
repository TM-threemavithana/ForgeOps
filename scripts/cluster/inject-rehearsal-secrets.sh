#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G08 — Guarded GitOps Rehearsal Secret Provisioning Script
# Injects database credentials exclusively into 'forgeops-gitops-rehearsal'
# Uses atomic create-only file-based injection (--from-file)
#
# Hardened Security Boundaries:
# 1. Fixed Credential Source: Strictly locked to ~/.config/forgeops/secrets/rehearsal_db_password.txt
#    No CLI override allowed; explicitly rejects G06 dev and G07 sandbox credential files.
# 2. Fixed Target Boundary: Strictly targets namespace 'forgeops-gitops-rehearsal' and context 'kind-forgeops'.
# 3. Native WSL Hygiene: Rejects Windows /mnt mounts and symbolic links; enforces mode 0600 (file) and 0700 (parent).
# 4. Strict Umask & Scoped Cleanup: Sets umask 077 before mktemp; cleanup removes only script-owned temp directory.
# 5. Atomic Create-Only: Uses direct 'kubectl create secret generic' (zero overwrite, zero rotation).
# 6. Process Hygiene: Zero password exposure in CLI arguments, process tables (/proc), or logs.
# 7. Operator Authorization: Requires explicit '--confirm' or 'CONFIRM_REHEARSAL_INJECT=yes'.
# 8. Dry-Run Verification: Provides '--validate-only' performing zero cluster mutations.
# ==============================================================================

set -euo pipefail

KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"
EXPECTED_CONTEXT="kind-forgeops"
SECRET_NAME="forgetasks-rehearsal-db-secret"
TARGET_NS="forgeops-gitops-rehearsal"

# Credential loading is strictly hardcoded to the rehearsal password file
APPROVED_SECRET_FILE="${HOME}/.config/forgeops/secrets/rehearsal_db_password.txt"
G06_SECRET_FILE="${HOME}/.config/forgeops/secrets/db_password.txt"
SANDBOX_SECRET_FILE="${HOME}/.config/forgeops/secrets/sandbox_db_password.txt"

VALIDATE_ONLY=false
CONFIRMED=false
TMP_DIR=""

# Scoped cleanup function ensuring removal of only script-created temporary directory
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    case "$TMP_DIR" in
      /tmp/forgeops-rehearsal-secret.*)
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
      echo "       Rehearsal secret injection is locked exclusively to:" >&2
      echo "       ${APPROVED_SECRET_FILE}" >&2
      exit 1
      ;;
    --namespace*|-n*)
      echo "ERROR: CLI namespace override is strictly forbidden." >&2
      echo "       Target namespace is fixed to: ${TARGET_NS}" >&2
      exit 1
      ;;
    *)
      echo "ERROR: Unrecognized argument: $1" >&2
      echo "Usage: $0 [--validate-only] [--confirm]" >&2
      exit 1
      ;;
  esac
done

if [ "${CONFIRM_REHEARSAL_INJECT:-no}" = "yes" ]; then
  CONFIRMED=true
fi

echo "=============================================================================="
echo " ForgeOps G08 — Guarded GitOps Rehearsal Secret Injector"
echo " Target Namespace: ${TARGET_NS}"
echo " Secret Object:    ${SECRET_NAME}"
echo " Validate Only:    ${VALIDATE_ONLY}"
echo " Confirmed:        ${CONFIRMED}"
echo "=============================================================================="

# 1. Kubeconfig and Context Verification (Skipped in validate-only mode)
if [ "$VALIDATE_ONLY" != true ]; then
  if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "[FAIL] Isolated kubeconfig '${KUBECONFIG_FILE}' not found." >&2
    echo "       Ensure Kind cluster is running." >&2
    exit 1
  fi

  CURRENT_CTX=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" config current-context 2>/dev/null || true)
  if [ "$CURRENT_CTX" != "$EXPECTED_CONTEXT" ]; then
    echo "[FAIL] Kubeconfig context mismatch. Expected '${EXPECTED_CONTEXT}', found '${CURRENT_CTX}'." >&2
    exit 1
  fi

  # 2. Namespace Existence Check
  if ! kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get namespace "${TARGET_NS}" >/dev/null 2>&1; then
    echo "[FAIL] Target rehearsal namespace '${TARGET_NS}' does not exist." >&2
    echo "       Create rehearsal namespace first via: kubectl apply -f platform/k8s/namespaces/forgeops-gitops-rehearsal.yaml" >&2
    exit 1
  fi
fi

# 3. Locate and Validate Rehearsal Password File
# Enforce native WSL path: reject Windows /mnt mounts
case "$APPROVED_SECRET_FILE" in
  /mnt/*|*/mnt/*)
    echo "[FAIL] Refusing credential path under Windows mount: '${APPROVED_SECRET_FILE}'." >&2
    exit 1
    ;;
esac

# Explicitly ensure we never read the G06 or G07 sandbox secret files
if [ "$APPROVED_SECRET_FILE" = "$G06_SECRET_FILE" ]; then
  echo "[FAIL] Rehearsal credential file must NOT match G06 credential file." >&2
  exit 1
fi
if [ "$APPROVED_SECRET_FILE" = "$SANDBOX_SECRET_FILE" ]; then
  echo "[FAIL] Rehearsal credential file must NOT match G07 sandbox credential file." >&2
  exit 1
fi

if [ ! -e "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Rehearsal credential file '${APPROVED_SECRET_FILE}' does not exist." >&2
  echo "       Please create it securely in native WSL:" >&2
  echo "         mkdir -p ~/.config/forgeops/secrets && chmod 0700 ~/.config/forgeops/secrets" >&2
  echo "         echo -n '<dedicated-strong-password>' > ~/.config/forgeops/secrets/rehearsal_db_password.txt" >&2
  echo "         chmod 0600 ~/.config/forgeops/secrets/rehearsal_db_password.txt" >&2
  exit 1
fi

# Reject symlinks
if [ -L "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Credential path '${APPROVED_SECRET_FILE}' is a symbolic link. Symlinks are forbidden." >&2
  exit 1
fi

if [ ! -f "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Credential path '${APPROVED_SECRET_FILE}' is not a regular file." >&2
  exit 1
fi

# Validate file ownership
CURRENT_UID=$(id -u)
FILE_UID=$(stat -c "%u" "$APPROVED_SECRET_FILE" 2>/dev/null || stat -f "%u" "$APPROVED_SECRET_FILE" 2>/dev/null || echo "")
if [ "$FILE_UID" != "$CURRENT_UID" ]; then
  echo "[FAIL] Credential file '${APPROVED_SECRET_FILE}' is owned by UID ${FILE_UID}, not current user UID ${CURRENT_UID}." >&2
  exit 1
fi

# Validate file permissions (mode 0600 or 0400)
FILE_PERMS=$(stat -c "%a" "$APPROVED_SECRET_FILE" 2>/dev/null || stat -f "%Lp" "$APPROVED_SECRET_FILE" 2>/dev/null || echo "000")
if [ "$FILE_PERMS" != "600" ] && [ "$FILE_PERMS" != "400" ]; then
  echo "[FAIL] Insecure file permissions (${FILE_PERMS}) on '${APPROVED_SECRET_FILE}'." >&2
  echo "       Permissions must be mode 0600 or stricter." >&2
  exit 1
fi

# Validate parent directory
PARENT_DIR="$(dirname "$APPROVED_SECRET_FILE")"
if [ -L "$PARENT_DIR" ]; then
  echo "[FAIL] Parent directory '${PARENT_DIR}' is a symbolic link." >&2
  exit 1
fi

PARENT_UID=$(stat -c "%u" "$PARENT_DIR" 2>/dev/null || stat -f "%u" "$PARENT_DIR" 2>/dev/null || echo "")
if [ "$PARENT_UID" != "$CURRENT_UID" ]; then
  echo "[FAIL] Parent directory '${PARENT_DIR}' is owned by UID ${PARENT_UID}, not ${CURRENT_UID}." >&2
  exit 1
fi

PARENT_PERMS=$(stat -c "%a" "$PARENT_DIR" 2>/dev/null || stat -f "%Lp" "$PARENT_DIR" 2>/dev/null || echo "000")
if [ "$PARENT_PERMS" != "700" ] && [ "$PARENT_PERMS" != "500" ]; then
  echo "[FAIL] Insecure parent directory permissions (${PARENT_PERMS}) on '${PARENT_DIR}'." >&2
  echo "       Parent directory must be mode 0700 or stricter." >&2
  exit 1
fi

# Validate file content is non-empty and single line
if [ ! -s "$APPROVED_SECRET_FILE" ]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' is empty." >&2
  exit 1
fi

NUM_LINES=0
FIRST_LINE=""
while IFS= read -r line || [ -n "$line" ]; do
  NUM_LINES=$((NUM_LINES + 1))
  if [ "$NUM_LINES" -eq 1 ]; then
    FIRST_LINE="$line"
  fi
done < "$APPROVED_SECRET_FILE"

if [ "$NUM_LINES" -gt 1 ]; then
  echo "[FAIL] Secret file '${APPROVED_SECRET_FILE}' contains multiple lines." >&2
  exit 1
fi

SANITIZED_PASS="${FIRST_LINE%$'\r'}"
if [[ "$SANITIZED_PASS" =~ [$'\r'$'\n'] ]]; then
  echo "[FAIL] Secret file contains embedded newline or carriage return characters." >&2
  exit 1
fi

if [ "${#SANITIZED_PASS}" -lt 8 ]; then
  echo "[FAIL] Password in '${APPROVED_SECRET_FILE}' is shorter than 8 characters." >&2
  exit 1
fi

echo "[1/2] Credential source verified: ${APPROVED_SECRET_FILE} (perms ${FILE_PERMS}, parent ${PARENT_PERMS})"

# Validate-only exit
if [ "$VALIDATE_ONLY" = true ]; then
  unset FIRST_LINE
  unset SANITIZED_PASS
  echo "=============================================================================="
  echo " STATUS: REHEARSAL CREDENTIAL VALIDATED (Zero cluster mutations)"
  echo "=============================================================================="
  exit 0
fi

# 4. Check for Existing Secret & Enforce Immutability
if kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" get secret "${SECRET_NAME}" -n "${TARGET_NS}" >/dev/null 2>&1; then
  echo "[INFO] Secret '${SECRET_NAME}' already exists in namespace '${TARGET_NS}'."
  echo "       Preserving existing Secret (atomic create-only, zero overwrite)."
  echo "=============================================================================="
  echo " STATUS: PRESERVED (Existing Secret untouched)"
  echo "=============================================================================="
  unset FIRST_LINE
  unset SANITIZED_PASS
  exit 0
fi

# Require explicit confirmation
if [ "$CONFIRMED" != true ]; then
  echo "[WARN] Secret creation not confirmed." >&2
  echo "       To create Secret '${SECRET_NAME}' in namespace '${TARGET_NS}', re-run with: --confirm" >&2
  exit 1
fi

# 5. Atomic Injection via Private Temp File
PREV_UMASK=$(umask)
umask 077
TMP_DIR=$(mktemp -d /tmp/forgeops-rehearsal-secret.XXXXXX)
umask "$PREV_UMASK"

TMP_PASS_FILE="${TMP_DIR}/postgres-password"
printf '%s' "$SANITIZED_PASS" > "$TMP_PASS_FILE"
chmod 0600 "$TMP_PASS_FILE"

unset FIRST_LINE
unset SANITIZED_PASS

echo "[2/2] Injecting Secret '${SECRET_NAME}' into namespace '${TARGET_NS}'..."

kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" \
  create secret generic "${SECRET_NAME}" \
  --namespace="${TARGET_NS}" \
  --from-file="postgres-password=${TMP_PASS_FILE}"

# Label Secret with ForgeOps governance metadata
kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="${EXPECTED_CONTEXT}" \
  label secret "${SECRET_NAME}" \
  --namespace="${TARGET_NS}" \
  "app.kubernetes.io/name=forgetasks-postgres" \
  "app.kubernetes.io/part-of=forgeops" \
  "forgeops.io/gate=G08" \
  "forgeops.io/role=rehearsal-secret" \
  --overwrite >/dev/null

echo "=============================================================================="
echo " STATUS: CREATED (Secret '${SECRET_NAME}' provisioned in '${TARGET_NS}')"
echo "=============================================================================="
