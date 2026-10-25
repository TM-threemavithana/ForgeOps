#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G06 — Kind Cluster Creation Script
# Safe, idempotent single-control-plane cluster creation with isolated kubeconfig
# Hardware checks: WSL memory >= 3.0 GiB, Windows C: free disk >= 10 GB
# ==============================================================================

set -euo pipefail

CLUSTER_NAME="forgeops"
KIND_CONFIG="platform/kind/cluster-config.yaml"
KUBECONFIG_DIR="${HOME}/.kube"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/config-forgeops"
MIN_MEM_MIB=3000
MIN_DISK_GB=10
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run|--preflight)
      DRY_RUN=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run|--preflight]" >&2
      exit 1
      ;;
  esac
done

echo "=============================================================================="
echo " ForgeOps G06 — Kind Cluster Provisioner"
echo " Target Cluster: ${CLUSTER_NAME}"
echo " Kubeconfig:     ${KUBECONFIG_FILE}"
echo " Dry-Run Mode:   ${DRY_RUN}"
echo "=============================================================================="

# 1. Prerequisite Tool Validation
echo "[1/6] Validating required toolchain..."
for tool in kind kubectl docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[FAIL] Mandatory tool '$tool' is not installed or not in PATH." >&2
    exit 1
  fi
done

KIND_VER=$(kind version)
KUBECTL_VER=$(kubectl version --client 2>/dev/null | head -n1)
DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unreachable")

echo "  - Kind:    ${KIND_VER}"
echo "  - kubectl: ${KUBECTL_VER}"
echo "  - Docker:  ${DOCKER_VER}"

if [ "$DOCKER_VER" = "unreachable" ]; then
  echo "[FAIL] Docker daemon is unreachable. Verify Docker Desktop / WSL2 integration." >&2
  exit 1
fi

# 2. Hardware Resource & Capacity Preflight
echo "[2/6] Inspecting WSL2 memory and host disk capacity..."
AVAIL_MEM_MIB=$(free -m | awk '/^Mem:/{print $7}')
echo "  - Available WSL2 memory: ${AVAIL_MEM_MIB} MiB (Minimum required: ${MIN_MEM_MIB} MiB)"

if [ "$AVAIL_MEM_MIB" -lt "$MIN_MEM_MIB" ]; then
  echo "[FAIL] Insufficient WSL2 memory. Available: ${AVAIL_MEM_MIB} MiB, required: ${MIN_MEM_MIB} MiB." >&2
  echo "       Stop other heavy processes before continuing (Rule 8: Core Profile)." >&2
  exit 1
fi

if [ -d "/mnt/c" ]; then
  FREE_DISK_GB=$(df -BG /mnt/c | awk 'NR==2 {gsub("G","",$4); print $4}')
  echo "  - Free space on drive C: ${FREE_DISK_GB} GB (Minimum required: ${MIN_DISK_GB} GB)"
  if [ "$FREE_DISK_GB" -lt "$MIN_DISK_GB" ]; then
    echo "[FAIL] Insufficient disk space on drive C:. Free: ${FREE_DISK_GB} GB, required: ${MIN_DISK_GB} GB." >&2
    exit 1
  fi
else
  FREE_DISK_GB=$(df -BG . | awk 'NR==2 {gsub("G","",$4); print $4}')
  echo "  - Free space on workspace mount: ${FREE_DISK_GB} GB"
fi

# Check Host Port 6443 Availability on 127.0.0.1
echo "  - Checking loopback port 6443 availability..."
if (exec 3<>/dev/tcp/127.0.0.1/6443) 2>/dev/null; then
  exec 3<&- && exec 3>&-
  echo "[FAIL] Host loopback port 6443 is already in use. Aborting to prevent port collision." >&2
  exit 1
else
  echo "  - [OK] Port 6443 is available on 127.0.0.1."
fi

# 3. Cluster Existence Check (Strict Idempotence & Collision Protection)
echo "[3/6] Checking existing Kind clusters..."
EXISTING_CLUSTERS=$(kind get clusters 2>/dev/null || true)

if echo "$EXISTING_CLUSTERS" | grep -qx "${CLUSTER_NAME}"; then
  echo "[WARN] Kind cluster '${CLUSTER_NAME}' already exists."
  echo "       To recreate cleanly, run: make cluster-delete CONFIRM=yes"
  echo "[STATUS] No action taken. Existing cluster preserved."
  exit 0
fi

if [ -n "$EXISTING_CLUSTERS" ]; then
  echo "[NOTE] Other Kind clusters detected: $(echo "$EXISTING_CLUSTERS" | tr '\n' ' ')"
  echo "       ForgeOps will NOT modify or touch any cluster other than '${CLUSTER_NAME}'."
fi

# 4. Configuration File Verification
echo "[4/6] Verifying Kind cluster configuration file..."
if [ ! -f "$KIND_CONFIG" ]; then
  echo "[FAIL] Configuration file '${KIND_CONFIG}' not found." >&2
  exit 1
fi

# 5. Kubeconfig Directory Preparation
mkdir -p "$KUBECONFIG_DIR"
chmod 0700 "$KUBECONFIG_DIR"

if [ "$DRY_RUN" = true ]; then
  echo "[5/6] DRY-RUN: Preflight checks passed. Cluster creation skipped."
  echo "=============================================================================="
  echo " STATUS: PREFLIGHT PASS (Dry-run complete — ready for execution)"
  echo "=============================================================================="
  exit 0
fi

# 6. Execute Kind Cluster Creation
echo "[5/6] Creating Kind cluster '${CLUSTER_NAME}'..."
kind create cluster \
  --name "${CLUSTER_NAME}" \
  --config "${KIND_CONFIG}" \
  --kubeconfig "${KUBECONFIG_FILE}"

chmod 0600 "${KUBECONFIG_FILE}"

echo "[6/6] Validating control-plane readiness..."
export KUBECONFIG="${KUBECONFIG_FILE}"

kubectl --kubeconfig="${KUBECONFIG_FILE}" --context="kind-${CLUSTER_NAME}" wait --for=condition=Ready node "${CLUSTER_NAME}-control-plane" --timeout=90s

echo "=============================================================================="
echo " STATUS: CLUSTER CREATED SUCCESSFULLY"
echo " Context:    kind-${CLUSTER_NAME}"
echo " Kubeconfig: ${KUBECONFIG_FILE} (chmod 0600)"
echo ""
echo " Recommended next commands:"
echo "   export KUBECONFIG=${KUBECONFIG_FILE}"
echo "   make cluster-load-images"
echo "   make k8s-dev-deploy"
echo "=============================================================================="
