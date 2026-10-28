#!/usr/bin/env bash
# ForgeOps Gate G13 - Setup Disposable Disaster Recovery Lab Fixture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/common-dr.sh"

TARGET_NS="${1:-$DISPOSABLE_DR_NAMESPACE}"
MODE="${2:-setup}"

echo "======================================================================="
echo "ForgeOps G13: Provision Disposable Disaster Recovery Lab"
echo "Target Namespace:      $TARGET_NS"
echo "Storage Strategy:      ephemeral emptyDir (STRICT ZERO PVCs)"
echo "Workloads:             dr-source-db, dr-target-db, dr-api"
echo "Dataset:               Synthetic test accounts, projects, and tasks"
echo "======================================================================="

# Step 1: Preflight guards
run_dr_preflight_guards "$TARGET_NS"

if [[ "$TARGET_NS" != "$DISPOSABLE_DR_NAMESPACE" ]]; then
  log_err "CRITICAL SAFETY REFUSAL: Target namespace '$TARGET_NS' must be '$DISPOSABLE_DR_NAMESPACE'!"
  exit 1
fi

if [[ "$MODE" == "--validate-only" || "$MODE" == "--dry-run" ]]; then
  log_info "Running setup-dr-lab in validation mode (dry-run)..."
  kubectl kustomize "${REPO_ROOT}/platform/dr-lab" >/dev/null
  log_pass "Kustomize manifest rendering validated successfully."
  exit 0
fi

# Step 2: Generate dynamic ephemeral credentials
log_info "Generating dynamic ephemeral credentials for disposable lab..."
EPHEMERAL_DB_PASS="dr-lab-$(openssl rand -hex 12)"

# Step 3: Deploy declarative manifests
log_info "Applying declarative manifests for $TARGET_NS..."
kubectl apply -k "${REPO_ROOT}/platform/dr-lab"

# Update secret with freshly generated ephemeral password
kubectl create secret generic dr-db-secret \
  -n "$TARGET_NS" \
  --from-literal=postgres-password="$EPHEMERAL_DB_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Step 4: Wait for database instances to become ready
log_info "Waiting for dr-source-db deployment to become Ready (up to 90s)..."
kubectl rollout status deployment/dr-source-db -n "$TARGET_NS" --timeout=90s

log_info "Waiting for dr-target-db deployment to become Ready (up to 90s)..."
kubectl rollout status deployment/dr-target-db -n "$TARGET_NS" --timeout=90s

# Step 5: Initialize source database schema and synthetic dataset
log_info "Initializing source database with production DDL schema and synthetic seed dataset..."
SOURCE_POD="$(kubectl get pods -n "$TARGET_NS" -l app=dr-source-db --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

# Run Flyway initial schema (V1__init_schema.sql)
kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" \
  psql -U forgeuser -d forgetasks -v ON_ERROR_STOP=1 < "${REPO_ROOT}/apps/forgetasks-api/src/main/resources/db/migration/V1__init_schema.sql"

# Simulate Flyway schema history entry for migration tracking
kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" \
  psql -U forgeuser -d forgetasks -v ON_ERROR_STOP=1 <<EOF
CREATE TABLE IF NOT EXISTS flyway_schema_history (
    installed_rank INT NOT NULL PRIMARY KEY,
    version VARCHAR(50),
    description VARCHAR(200) NOT NULL,
    type VARCHAR(20) NOT NULL,
    script VARCHAR(1000) NOT NULL,
    checksum INT,
    installed_by VARCHAR(100) NOT NULL,
    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    execution_time INT NOT NULL,
    success BOOLEAN NOT NULL
);
INSERT INTO flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, execution_time, success)
VALUES (1, '1', 'init schema', 'SQL', 'V1__init_schema.sql', 12345678, 'forgeuser', 42, true)
ON CONFLICT (installed_rank) DO NOTHING;
EOF

# Insert synthetic accounts, projects, tasks
kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" \
  psql -U forgeuser -d forgetasks -v ON_ERROR_STOP=1 < "${REPO_ROOT}/platform/dr-lab/synthetic-seed.sql"

# Step 6: Verify source data counts
SRC_ACCOUNTS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM accounts;" | xargs)"
SRC_PROJECTS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM projects;" | xargs)"
SRC_TASKS="$(kubectl exec -i "$SOURCE_POD" -n "$TARGET_NS" -- env PGPASSWORD="$EPHEMERAL_DB_PASS" psql -U forgeuser -d forgetasks -t -c "SELECT count(*) FROM tasks;" | xargs)"

log_info "Source Database Seed Inventory:"
log_info "  - accounts: $SRC_ACCOUNTS"
log_info "  - projects: $SRC_PROJECTS"
log_info "  - tasks:    $SRC_TASKS"

# Step 7: Strict zero PVC verification
assert_no_pvc_in_disposable_ns "$TARGET_NS"

# Step 8: Assert protected PVCs intact
assert_protected_pvcs_intact

log_pass "Disposable Disaster Recovery Lab Provisioned Successfully in '$TARGET_NS' (0 PVCs)!"
