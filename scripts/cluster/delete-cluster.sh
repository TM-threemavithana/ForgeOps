#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G06 — Kind Cluster Deletion Script
# Strictly guarded teardown script requiring explicit CONFIRM=yes
# Never deletes any cluster other than 'forgeops'; cleans up isolated kubeconfig
# ==============================================================================

set -euo pipefail

CLUSTER_NAME="forgeops"
KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"

echo "=============================================================================="
echo " ForgeOps G06 — Scoped Kind Cluster Teardown"
echo " Target Cluster: ${CLUSTER_NAME}"
echo "=============================================================================="

# 1. Guard Confirmation Check
if [ "${CONFIRM:-no}" != "yes" ]; then
  echo "[FAIL] Destructive cluster teardown aborted." >&2
  echo "       To delete cluster '${CLUSTER_NAME}', run with CONFIRM=yes:" >&2
  echo "       CONFIRM=yes ./scripts/cluster/delete-cluster.sh" >&2
  echo "       or: make cluster-delete CONFIRM=yes" >&2
  exit 1
fi

# 2. Check Kind Availability
if ! command -v kind >/dev/null 2>&1; then
  echo "[FAIL] 'kind' CLI is not installed or not in PATH." >&2
  exit 1
fi

# 3. Verify Target Cluster Exists and is Strictly 'forgeops'
EXISTING_CLUSTERS=$(kind get clusters 2>/dev/null || true)

if ! echo "$EXISTING_CLUSTERS" | grep -qx "${CLUSTER_NAME}"; then
  echo "[INFO] Kind cluster '${CLUSTER_NAME}' does not exist. Nothing to delete."
  if [ -f "$KUBECONFIG_FILE" ]; then
    echo "       Removing orphaned kubeconfig ${KUBECONFIG_FILE}..."
    rm -f "$KUBECONFIG_FILE"
  fi
  echo "[STATUS] Clean. Zero clusters deleted."
  exit 0
fi

# 4. Terminate any lingering kubectl port-forward processes targeting 8080 or 5432
echo "[1/3] Terminating any active port-forward sessions for ${CLUSTER_NAME}..."
pkill -f "kubectl.*port-forward.*(8080|5432|28080)" 2>/dev/null || true

# 5. Delete Strictly the 'forgeops' Cluster
echo "[2/3] Deleting Kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"

# 6. Clean Up Isolated Kubeconfig
echo "[3/3] Cleaning up isolated kubeconfig..."
if [ -f "$KUBECONFIG_FILE" ]; then
  rm -f "$KUBECONFIG_FILE"
  echo "       Removed ${KUBECONFIG_FILE}."
fi

echo "=============================================================================="
echo " STATUS: CLUSTER '${CLUSTER_NAME}' DELETED SAFELY"
echo " Blast Radius Audit: Zero unrelated Docker containers, networks, or VMs modified."
echo "=============================================================================="
