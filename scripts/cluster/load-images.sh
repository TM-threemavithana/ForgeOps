#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G06 — Offline Image Loader
# Loads local Docker images into Kind node containerd using single-platform archives
# Resolves Docker Desktop containerd image store compatibility (multi-arch digest error)
# ==============================================================================

set -euo pipefail

CLUSTER_NAME="forgeops"
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"
EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"

API_IMAGE="forgetasks-api:1.0.0"
POSTGRES_IMAGE="postgres:16-alpine"
FORCE_RELOAD=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE_RELOAD=true
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--force]" >&2
      exit 1
      ;;
  esac
done

echo "=============================================================================="
echo " ForgeOps G06 — Offline Image Loader"
echo " Target Cluster:   ${CLUSTER_NAME}"
echo " Expected Context: ${EXPECTED_CONTEXT}"
echo " Force Reload:     ${FORCE_RELOAD}"
echo "=============================================================================="

# 1. Target Cluster & Node Verification
if [ "${CLUSTER_NAME}" != "forgeops" ]; then
  echo "[FAIL] Target cluster must be strictly 'forgeops'." >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "[FAIL] Kind cluster '${CLUSTER_NAME}' is not running." >&2
  echo "       Create it first via: make cluster-create" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "${NODE_CONTAINER}"; then
  echo "[FAIL] Kind node container '${NODE_CONTAINER}' is not running." >&2
  exit 1
fi

# 2. Node Architecture Detection
echo "[1/4] Detecting Kind node architecture..."
NODE_ARCH=$(docker exec "${NODE_CONTAINER}" uname -m 2>/dev/null || uname -m)
echo "  - Kind Node Kernel Arch: ${NODE_ARCH}"

case "$NODE_ARCH" in
  x86_64|amd64)
    TARGET_PLATFORM="linux/amd64"
    ;;
  aarch64|arm64)
    TARGET_PLATFORM="linux/arm64"
    ;;
  *)
    echo "[FAIL] Unsupported node architecture '${NODE_ARCH}'. Aborting to prevent loading incompatible images." >&2
    exit 1
    ;;
esac
echo "  - Target Single-Platform: ${TARGET_PLATFORM}"

# 3. Verify Local Docker Engine Images
echo "[2/4] Verifying presence of required images in local Docker daemon..."

for img in "${API_IMAGE}" "${POSTGRES_IMAGE}"; do
  if ! docker image inspect "${img}" >/dev/null 2>&1; then
    echo "[FAIL] Required image '${img}' is missing from local Docker Engine." >&2
    if [ "$img" = "$API_IMAGE" ]; then
      echo "       Build the API image using: cd apps/forgetasks-api && ./mvnw clean package -DskipTests && docker build -t ${API_IMAGE} ." >&2
    else
      echo "       Pull the verified Postgres image using: docker pull postgres:16-alpine" >&2
    fi
    exit 1
  fi
  IMG_ID=$(docker image inspect "${img}" --format '{{.Id}}' | cut -c1-19)
  echo "  - [OK] ${img} (ID: ${IMG_ID})"
done

# 4. Check If Images Already Exist in Kind containerd
check_image_loaded() {
  local target="$1"
  local repo="${target%:*}"
  local tag="${target##*:}"
  docker exec "${NODE_CONTAINER}" crictl images 2>/dev/null | \
    awk '{print $1":"$2}' | \
    grep -E "(docker\.io/library/${repo}|${repo}):${tag}" >/dev/null 2>&1
}

API_LOADED=false
PG_LOADED=false

if check_image_loaded "${API_IMAGE}"; then
  API_LOADED=true
fi
if check_image_loaded "${POSTGRES_IMAGE}"; then
  PG_LOADED=true
fi

if [ "$API_LOADED" = true ] && [ "$PG_LOADED" = true ] && [ "$FORCE_RELOAD" = false ]; then
  echo "[3/4] Both images are already loaded in Kind node containerd:"
  echo "  - ${API_IMAGE}: PRESENT"
  echo "  - ${POSTGRES_IMAGE}: PRESENT"
  echo "       Skipping export/import (safely repeatable). Pass --force to reload."
else
  # 5. Export and Load Images via Single-Platform Archives
  echo "[3/4] Exporting single-platform archive (${TARGET_PLATFORM}) and loading into Kind..."

  TMP_DIR=$(mktemp -d /tmp/forgeops-img-load.XXXXXX)
  cleanup() {
    if [ -d "$TMP_DIR" ]; then
      rm -rf "$TMP_DIR"
    fi
  }
  trap cleanup EXIT

  load_single_image() {
    local img="$1"
    local safe_name
    safe_name=$(echo "$img" | tr '/:' '_')
    local archive="${TMP_DIR}/${safe_name}.tar"

    echo "  - Exporting '${img}' for platform ${TARGET_PLATFORM} to temporary archive..."
    docker image save --platform "${TARGET_PLATFORM}" --output "${archive}" "${img}"

    echo "  - Importing archive into Kind cluster '${CLUSTER_NAME}' via containerd..."
    kind load image-archive "${archive}" --name "${CLUSTER_NAME}"

    rm -f "${archive}"
  }

  if [ "$API_LOADED" = false ] || [ "$FORCE_RELOAD" = true ]; then
    load_single_image "${API_IMAGE}"
  else
    echo "  - ${API_IMAGE}: already present in containerd."
  fi

  if [ "$PG_LOADED" = false ] || [ "$FORCE_RELOAD" = true ]; then
    load_single_image "${POSTGRES_IMAGE}"
  else
    echo "  - ${POSTGRES_IMAGE}: already present in containerd."
  fi
fi

# 6. Verify Images Inside Kind Node containerd
echo "[4/4] Verifying containerd image cache inside '${NODE_CONTAINER}'..."
CONTAINERD_IMAGES=$(docker exec "${NODE_CONTAINER}" crictl images)

echo "$CONTAINERD_IMAGES" | head -n 1
echo "$CONTAINERD_IMAGES" | grep -E "(forgetasks-api|postgres)" || true

if ! check_image_loaded "${API_IMAGE}" || ! check_image_loaded "${POSTGRES_IMAGE}"; then
  echo "[FAIL] Verification failed: one or more required images not found in containerd." >&2
  exit 1
fi

echo "=============================================================================="
echo " STATUS: OFFLINE IMAGES VERIFIED IN KIND CLUSTER"
echo " Both workloads can resolve images locally via 'imagePullPolicy: IfNotPresent'."
echo " Zero external registry pulls required; zero unrelated Docker resources touched."
echo "=============================================================================="
