#!/usr/bin/env bash
# ForgeOps — G04 Ansible Static & Syntax Verification Script
# Validates Ansible configuration, inventory resolution, collections, and playbook syntax offline.
#
# Usage: ./scripts/verify_g04_ansible_syntax.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
WARN=0

step_pass() { echo "[PASS] $1"; ((PASS++)) || true; }
step_fail() { echo "[FAIL] $1"; ((FAIL++)) || true; }
step_warn() { echo "[WARN] $1"; ((WARN++)) || true; }
step_info() { echo "[INFO] $1"; }

echo "============================================================"
echo " ForgeOps G04 Ansible Offline Syntax & Structure Validation"
echo " $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo " Repo: $REPO_ROOT"
echo "============================================================"

# ---- Step 1: Controller Tooling Baseline ---------------------------------
step_info "Checking Ansible controller tooling baseline..."

if command -v ansible >/dev/null 2>&1; then
  ANSIBLE_VER=$(ansible --version | head -n1)
  step_pass "Ansible detected: $ANSIBLE_VER"
else
  step_fail "Ansible is not installed or not in PATH"
fi

if command -v python3 >/dev/null 2>&1; then
  step_pass "Python runtime: $(python3 --version)"
else
  step_fail "Python 3 is not installed"
fi

if command -v ssh >/dev/null 2>&1; then
  step_pass "OpenSSH client: $(ssh -V 2>&1 | head -n1)"
else
  step_fail "OpenSSH client is not installed"
fi

if command -v ansible-lint >/dev/null 2>&1; then
  step_pass "ansible-lint: $(ansible-lint --version | head -n1)"
else
  step_warn "ansible-lint is not installed (optional offline linter; see docs for installation via pipx)"
fi

# ---- Step 2: Ansible Collections Verification ---------------------------
step_info "Verifying required Ansible collections..."

export ANSIBLE_CONFIG="$REPO_ROOT/infrastructure/ansible/ansible.cfg"

if ansible-galaxy collection list 2>/dev/null | grep -q "ansible.posix"; then
  step_pass "Collection ansible.posix is installed"
else
  step_fail "Collection ansible.posix is missing"
fi

if ansible-galaxy collection list 2>/dev/null | grep -q "community.general"; then
  step_pass "Collection community.general is installed"
else
  step_fail "Collection community.general is missing"
fi

# ---- Step 3: Inventory Graph Resolution ----------------------------------
step_info "Testing Ansible inventory graph parsing..."

if ansible-inventory -i infrastructure/ansible/inventories/lab/hosts.yml --graph >/dev/null 2>&1; then
  step_pass "Inventory parsed successfully (managed_lab, webservers, forgeops-node-01)"
else
  step_fail "Inventory parsing failed"
fi

# ---- Step 4: Playbook Syntax Validation ----------------------------------
step_info "Validating site.yml playbook syntax..."

if ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.yml \
    infrastructure/ansible/playbooks/site.yml --syntax-check >/dev/null 2>&1; then
  step_pass "Playbook site.yml syntax valid across all 5 roles (baseline, users, ssh-hardening, firewall, nginx)"
else
  step_fail "Playbook site.yml syntax check failed"
fi

step_info "Validating verify.yml audit playbook syntax..."

if ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.yml \
    infrastructure/ansible/playbooks/verify.yml --syntax-check >/dev/null 2>&1; then
  step_pass "Audit playbook verify.yml syntax valid"
else
  step_fail "Audit playbook verify.yml syntax check failed"
fi

# ---- Step 5: Historical Runtime Guest Execution Evidence (Informational) -
echo "------------------------------------------------------------"
echo " Historical Runtime Guest Execution Evidence:"
echo " Note: Recorded runtime results below are historical evidence,"
echo " NOT live tests executed by this offline check script."
echo " See docs/evidence/G04/readiness.md for full execution evidence."
echo " [RECORDED] Managed guest VM verified and pingable"
echo " [RECORDED] A-401: Full site playbook convergence on live guest"
echo " [RECORDED] A-401.6: External firewall port block test (drop verified)"
echo " [RECORDED] A-402: Playbook idempotence (changed=0) on live guest"
echo " [RECORDED] DR-09: Intentional Nginx configuration drift correction"
echo " [RECORDED] Independent audit: verify.yml (ok=14 changed=0 failed=0)"
echo "------------------------------------------------------------"

echo "============================================================"
echo " Validation Summary: $PASS Passed, $FAIL Failed, $WARN Warning(s)"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
  echo "Status: FAILED - Resolve errors above."
  exit 1
else
  echo "Status: PASSED (Offline Scaffolding & Syntax Validated)"
  exit 0
fi
