#!/usr/bin/env bash
# ForgeOps Gate G09.3: Pre-Commit Hook Installer & Setup Script (POSIX / WSL2)
# Configures Git core.hooksPath to .githooks and installs pinned Gitleaks binary if needed.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOKS_DIR="${REPO_ROOT}/.githooks"
GITLEAKS_VERSION="8.24.3"
GITLEAKS_SHA256="9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c"

echo "=== ForgeOps Pre-Commit Hook Setup (Gitleaks) ==="

# 1. Configure git hooks directory
echo "--> Configuring git core.hooksPath to '${HOOKS_DIR}'..."
git config core.hooksPath .githooks
chmod +x "${HOOKS_DIR}/pre-commit"
echo "  [PASS] Git core.hooksPath successfully configured."

# 2. Check for Gitleaks installation
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "${INSTALL_DIR}"

if command -v gitleaks >/dev/null 2>&1; then
    CURRENT_VERSION="$(gitleaks version 2>/dev/null || echo 'unknown')"
    echo "  [PASS] Gitleaks already installed: ${CURRENT_VERSION} ($(command -v gitleaks))"
elif [ -x "${INSTALL_DIR}/gitleaks" ]; then
    CURRENT_VERSION="$("${INSTALL_DIR}/gitleaks" version 2>/dev/null || echo 'unknown')"
    echo "  [PASS] Pinned Gitleaks installed in ${INSTALL_DIR}/gitleaks: ${CURRENT_VERSION}"
else
    echo "--> Gitleaks binary not found. Downloading pinned v${GITLEAKS_VERSION} for linux_x64..."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT

    ARCHIVE="${TMP_DIR}/gitleaks.tar.gz"
    URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"

    curl -sSfL "${URL}" -o "${ARCHIVE}"

    # Verify authentic SHA-256
    echo "${GITLEAKS_SHA256}  ${ARCHIVE}" | sha256sum -c -

    tar -xzf "${ARCHIVE}" -C "${TMP_DIR}" gitleaks
    mv "${TMP_DIR}/gitleaks" "${INSTALL_DIR}/gitleaks"
    chmod +x "${INSTALL_DIR}/gitleaks"

    echo "  [PASS] Gitleaks v${GITLEAKS_VERSION} installed to ${INSTALL_DIR}/gitleaks with verified checksum."
fi

echo "================================================="
echo " Pre-commit secret scanning is active and ready! "
echo "================================================="
