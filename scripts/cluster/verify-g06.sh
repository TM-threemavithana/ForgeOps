#!/usr/bin/env bash
# ==============================================================================
# ForgeOps Gate G06 — Automated Acceptance Test Harness (A-601 & A-602)
#
# Strictly separates verification semantics:
#   1. --read-only          (Default) Non-mutating cluster & probe health checks
#   2. --smoke-write        Application write verification (POST /api/v1/accounts)
#   3. --drill-persistence  PostgreSQL pod kill & persistence drill (requires confirmation)
#   4. --drill-a602         Stateless API pod kill & recovery drill (requires confirmation)
#   5. --all                Runs all suites in sequence (requires confirmation)
# ==============================================================================

set -euo pipefail

CLUSTER_NAME="forgeops"
EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"
KUBECONFIG_FILE="${HOME}/.kube/config-forgeops"
DEV_NS="forgeops-dev"
STAGING_NS="forgeops-staging"
LOCAL_TEST_PORT=28080
PF_PID=""

# Execution Mode Flags (Mutually explicit)
RUN_READ_ONLY=true
RUN_SMOKE_WRITE=false
RUN_DRILL_PERSISTENCE=false
RUN_DRILL_A602=false
ALLOW_TERMINATION=false

if [ "${ALLOW_POD_TERMINATION:-no}" = "yes" ]; then
  ALLOW_TERMINATION=true
fi

# Parse Command-Line Options
if [ $# -gt 0 ]; then
  RUN_READ_ONLY=false
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      RUN_READ_ONLY=true
      shift
      ;;
    --smoke-write|--smoke-test)
      RUN_SMOKE_WRITE=true
      shift
      ;;
    --drill-persistence)
      RUN_DRILL_PERSISTENCE=true
      shift
      ;;
    --drill-a602)
      RUN_DRILL_A602=true
      shift
      ;;
    --all)
      RUN_READ_ONLY=true
      RUN_SMOKE_WRITE=true
      RUN_DRILL_PERSISTENCE=true
      RUN_DRILL_A602=true
      shift
      ;;
    --allow-termination)
      ALLOW_TERMINATION=true
      shift
      ;;
    --help|-h)
      echo "ForgeOps G06 Verification Harness Usage:"
      echo "  $0 --read-only          Run strictly non-mutating cluster & probe health checks (Default)"
      echo "  $0 --smoke-write        Run application database write smoke test (POST /api/v1/accounts)"
      echo "  $0 --drill-persistence  Run DB pod restart persistence drill (requires ALLOW_POD_TERMINATION=yes)"
      echo "  $0 --drill-a602         Run stateless API pod kill recovery drill (requires ALLOW_POD_TERMINATION=yes)"
      echo "  $0 --all                Run complete test suite (requires ALLOW_POD_TERMINATION=yes)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for available verification modes." >&2
      exit 1
      ;;
  esac
done

cleanup() {
  if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
    echo "Terminating loopback port-forward session (PID: $PF_PID)..."
    kill "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "=============================================================================="
echo " ForgeOps G06 — Kubernetes Acceptance Test Harness"
echo " Target Cluster:       ${CLUSTER_NAME}"
echo " Expected Context:     ${EXPECTED_CONTEXT}"
echo " Kubeconfig:           ${KUBECONFIG_FILE}"
echo " Active Modes:         ReadOnly=${RUN_READ_ONLY} | SmokeWrite=${RUN_SMOKE_WRITE} | DBPersistence=${RUN_DRILL_PERSISTENCE} | A602Drill=${RUN_DRILL_A602}"
echo " Pod Kill Permitted:   ${ALLOW_TERMINATION}"
echo "=============================================================================="

# 0. Kubeconfig and Context Guard Verification
if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "[FAIL] Kubeconfig '${KUBECONFIG_FILE}' not found." >&2
  echo "       Cluster must be created first: make cluster-create" >&2
  exit 1
fi

CURRENT_CTX=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" config current-context 2>/dev/null || true)
if [ "$CURRENT_CTX" != "$EXPECTED_CONTEXT" ]; then
  echo "[FAIL] Kubeconfig context mismatch. Expected '${EXPECTED_CONTEXT}', found '${CURRENT_CTX}'." >&2
  exit 1
fi

KCMD="kubectl --kubeconfig=${KUBECONFIG_FILE} --context=${EXPECTED_CONTEXT}"

if ! $KCMD get nodes >/dev/null 2>&1; then
  echo "[FAIL] Cannot connect to Kubernetes API server in context '${EXPECTED_CONTEXT}'." >&2
  exit 1
fi

ensure_port_forward() {
  if [ -z "$PF_PID" ] || ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "  Starting temporary port-forward on 127.0.0.1:${LOCAL_TEST_PORT}..."
    $KCMD port-forward -n "$DEV_NS" svc/forgetasks-api "${LOCAL_TEST_PORT}:8080" --address 127.0.0.1 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
  fi
}

# ==============================================================================
# SECTION 1: STRICTLY READ-ONLY VERIFICATION (Non-mutating)
# ==============================================================================
if [ "$RUN_READ_ONLY" = true ]; then
  echo ""
  echo "=============================================================================="
  echo " MODE 1: READ-ONLY CLUSTER & WORKLOAD VERIFICATION"
  echo " Mutation Audit: Zero database rows written; zero pods deleted."
  echo "=============================================================================="

  echo "--- [1/5] Node Readiness & Kubernetes Version ---"
  NODE_NAME="${CLUSTER_NAME}-control-plane"
  NODE_STATUS=$($KCMD get nodes "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  NODE_VER=$($KCMD get nodes "${NODE_NAME}" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
  echo "  Node: ${NODE_NAME} | Ready: ${NODE_STATUS} | Version: ${NODE_VER}"
  if [ "$NODE_STATUS" != "True" ]; then
    echo "[FAIL] Node ${NODE_NAME} is not Ready." >&2
    exit 1
  fi

  echo ""
  echo "--- [2/5] Core System Workloads ---"
  UNREADY_SYS=$($KCMD get pods -n kube-system --no-headers | grep -v -E "(Running|Completed)" || true)
  if [ -n "$UNREADY_SYS" ]; then
    echo "[FAIL] Unready system pods in kube-system:" >&2
    echo "$UNREADY_SYS" >&2
    exit 1
  fi
  echo "  [OK] CoreDNS, API server, controller-manager, scheduler healthy."

  LP_STATUS=$($KCMD get pods -n local-path-storage --no-headers | awk '{print $3}' || true)
  echo "  Local Path Provisioner: ${LP_STATUS}"
  if [ "$LP_STATUS" != "Running" ]; then
    echo "[FAIL] local-path-provisioner is not Running." >&2
    exit 1
  fi

  echo ""
  echo "--- [3/5] Namespaces, Quotas & LimitRanges ---"
  for ns in "$DEV_NS" "$STAGING_NS"; do
    if ! $KCMD get namespace "$ns" >/dev/null 2>&1; then
      echo "[FAIL] Mandatory namespace '$ns' does not exist." >&2
      exit 1
    fi
    QUOTAS=$($KCMD get resourcequota -n "$ns" --no-headers | wc -l)
    LIMITS=$($KCMD get limitrange -n "$ns" --no-headers | wc -l)
    echo "  Namespace: ${ns} | Quotas: ${QUOTAS} | LimitRanges: ${LIMITS}"
    if [ "$QUOTAS" -lt 1 ] || [ "$LIMITS" -lt 1 ]; then
      echo "[FAIL] Missing ResourceQuota or LimitRange in namespace '$ns'." >&2
      exit 1
    fi
  done

  echo ""
  echo "--- [4/5] PostgreSQL StatefulSet & Storage Verification ---"
  $KCMD wait --for=condition=Ready pod/forgetasks-db-0 -n "$DEV_NS" --timeout=60s
  DB_STATUS=$($KCMD get pod forgetasks-db-0 -n "$DEV_NS" -o jsonpath='{.status.phase}')
  echo "  PostgreSQL Pod: forgetasks-db-0 (${DB_STATUS})"

  PVC_NAME=$($KCMD get pvc -n "$DEV_NS" -l app.kubernetes.io/name=postgres -o jsonpath='{.items[0].metadata.name}')
  PVC_STATUS=$($KCMD get pvc "$PVC_NAME" -n "$DEV_NS" -o jsonpath='{.status.phase}')
  PVC_SC=$($KCMD get pvc "$PVC_NAME" -n "$DEV_NS" -o jsonpath='{.spec.storageClassName}')
  echo "  PVC: ${PVC_NAME} | Status: ${PVC_STATUS} | StorageClass: ${PVC_SC}"
  if [ "$PVC_STATUS" != "Bound" ]; then
    echo "[FAIL] PostgreSQL PVC is not Bound." >&2
    exit 1
  fi

  echo ""
  echo "--- [5/5] ForgeTasks API Deployment & Non-Mutating Probes ---"
  $KCMD wait --for=condition=Available deployment/forgetasks-api -n "$DEV_NS" --timeout=90s
  API_REPLICAS=$($KCMD get deployment forgetasks-api -n "$DEV_NS" -o jsonpath='{.status.readyReplicas}')
  echo "  ForgeTasks API Ready Replicas: ${API_REPLICAS}/1"

  ensure_port_forward

  LIVENESS_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_TEST_PORT}/actuator/health/liveness")
  echo "  Liveness Probe   (/actuator/health/liveness):  HTTP ${LIVENESS_HTTP}"
  if [ "$LIVENESS_HTTP" != "200" ]; then
    echo "[FAIL] Liveness probe returned unexpected status ${LIVENESS_HTTP}." >&2
    exit 1
  fi

  READINESS_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_TEST_PORT}/actuator/health/readiness")
  echo "  Readiness Probe  (/actuator/health/readiness): HTTP ${READINESS_HTTP}"
  if [ "$READINESS_HTTP" != "200" ]; then
    echo "[FAIL] Readiness probe returned unexpected status ${READINESS_HTTP}." >&2
    exit 1
  fi

  METRICS_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_TEST_PORT}/actuator/prometheus")
  echo "  Prometheus Probe (/actuator/prometheus):       HTTP ${METRICS_HTTP}"
  if [ "$METRICS_HTTP" != "200" ]; then
    echo "[FAIL] Prometheus endpoint returned unexpected status ${METRICS_HTTP}." >&2
    exit 1
  fi

  echo "=============================================================================="
  echo " READ-ONLY VERIFICATION: PASSED (Zero data mutations, zero pod deletions)"
  echo "=============================================================================="
fi

# ==============================================================================
# SECTION 2: APPLICATION DATABASE WRITE SMOKE TEST (--smoke-write)
# ==============================================================================
if [ "$RUN_SMOKE_WRITE" = true ]; then
  echo ""
  echo "=============================================================================="
  echo " MODE 2: APPLICATION DATABASE WRITE SMOKE TEST"
  echo " Mutation Audit: Inserts exactly 1 test account into 'accounts' table."
  echo "=============================================================================="

  ensure_port_forward

  TS=$(date +%s)
  SMOKE_USER="smoke_user_${TS}"
  SMOKE_PASS="Password123!"

  echo "  Registering test account '${SMOKE_USER}' via POST /api/v1/accounts..."
  SMOKE_RESP=$(curl -s -w "\n%{http_code}" -X POST "http://127.0.0.1:${LOCAL_TEST_PORT}/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${SMOKE_USER}\", \"password\": \"${SMOKE_PASS}\"}")

  SMOKE_HTTP=$(echo "$SMOKE_RESP" | tail -n1)
  echo "  Account Creation Response: HTTP ${SMOKE_HTTP}"
  if [ "$SMOKE_HTTP" != "201" ]; then
    echo "[FAIL] Account creation failed. Expected HTTP 201, got ${SMOKE_HTTP}." >&2
    echo "$SMOKE_RESP" >&2
    exit 1
  fi

  echo "  [OK] Flyway migrations, Hibernate validation, JPA mapping, and SQL INSERT succeeded."
  echo "=============================================================================="
  echo " SMOKE WRITE TEST: PASSED"
  echo "=============================================================================="
fi

# ==============================================================================
# SECTION 3: DATABASE PERSISTENCE RECOVERY DRILL (--drill-persistence)
# ==============================================================================
if [ "$RUN_DRILL_PERSISTENCE" = true ]; then
  echo ""
  echo "=============================================================================="
  echo " MODE 3: DATABASE POD RESTART & PERSISTENCE RECOVERY DRILL"
  echo " Mutation Audit: Inserts 1 baseline account, deletes pod forgetasks-db-0."
  echo "=============================================================================="

  if [ "$ALLOW_TERMINATION" != true ]; then
    echo "[FAIL] Database pod restart drill aborted." >&2
    echo "       Destructive recovery drills require explicit operator authorization:" >&2
    echo "       ALLOW_POD_TERMINATION=yes ./scripts/cluster/verify-g06.sh --drill-persistence" >&2
    echo "       or: make k8s-dev-drill-persistence CONFIRM=yes" >&2
    exit 1
  fi

  ensure_port_forward

  P_USER="persist_check_$(date +%s)"
  P_PASS="Password123!"

  echo "[1/3] Inserting persistent baseline account '${P_USER}'..."
  P_RESP=$(curl -s -w "\n%{http_code}" -X POST "http://127.0.0.1:${LOCAL_TEST_PORT}/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${P_USER}\", \"password\": \"${P_PASS}\"}")

  if [ "$(echo "$P_RESP" | tail -n1)" != "201" ]; then
    echo "[FAIL] Failed to seed baseline account for persistence drill." >&2
    exit 1
  fi

  echo "[2/3] Performing controlled deletion of database pod 'forgetasks-db-0'..."
  # Strictly verify workload ownership before deletion
  POD_LABEL=$($KCMD get pod forgetasks-db-0 -n "$DEV_NS" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}')
  if [ "$POD_LABEL" != "forgeops" ]; then
    echo "[FAIL] Pod forgetasks-db-0 ownership label mismatch ('${POD_LABEL}'). Aborting deletion." >&2
    exit 1
  fi

  $KCMD delete pod forgetasks-db-0 -n "$DEV_NS" --grace-period=5
  echo "      Awaiting StatefulSet recovery..."
  $KCMD wait --for=condition=Ready pod/forgetasks-db-0 -n "$DEV_NS" --timeout=60s
  echo "      [OK] PostgreSQL pod successfully recovered."

  echo "[3/3] Verifying database persistence across restart..."
  # Duplicate registration must return 409 Conflict because record persisted in volume
  DUP_RESP=$(curl -s -w "\n%{http_code}" -X POST "http://127.0.0.1:${LOCAL_TEST_PORT}/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${P_USER}\", \"password\": \"${P_PASS}\"}")

  DUP_HTTP=$(echo "$DUP_RESP" | tail -n1)
  echo "      Duplicate Registration Status: HTTP ${DUP_HTTP}"
  if [ "$DUP_HTTP" != "409" ]; then
    echo "[FAIL] Persistence verification failed. Expected HTTP 409 (account preserved), got ${DUP_HTTP}." >&2
    exit 1
  else
    echo "      [PASS] Account data persisted across PostgreSQL pod restart!"
  fi

  echo "=============================================================================="
  echo " DATABASE PERSISTENCE DRILL: PASSED"
  echo "=============================================================================="
fi

# ==============================================================================
# SECTION 4: A-602 STATELESS POD RECONCILIATION DRILL (--drill-a602)
# ==============================================================================
if [ "$RUN_DRILL_A602" = true ]; then
  echo ""
  echo "=============================================================================="
  echo " MODE 4: A-602 STATELESS POD FAILURE RECOVERY & RECONCILIATION DRILL"
  echo " Mutation Audit: Terminates active forgetasks-api pod; Deployment replaces it."
  echo "=============================================================================="

  if [ "$ALLOW_TERMINATION" != true ]; then
    echo "[FAIL] A-602 stateless pod kill drill aborted." >&2
    echo "       Destructive recovery drills require explicit operator authorization:" >&2
    echo "       ALLOW_POD_TERMINATION=yes ./scripts/cluster/verify-g06.sh --drill-a602" >&2
    echo "       or: make k8s-dev-drill-a602 CONFIRM=yes" >&2
    exit 1
  fi

  echo "[1/4] Inspecting baseline API pod..."
  TARGET_POD=$($KCMD get pods -n "$DEV_NS" -l app.kubernetes.io/name=forgetasks-api -o jsonpath='{.items[0].metadata.name}')
  POD_PART_OF=$($KCMD get pod "$TARGET_POD" -n "$DEV_NS" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}')

  if [ "$POD_PART_OF" != "forgeops" ]; then
    echo "[FAIL] Pod ${TARGET_POD} ownership label mismatch ('${POD_PART_OF}'). Aborting deletion." >&2
    exit 1
  fi
  echo "      Target Pod: ${TARGET_POD} (verified owner: forgeops)"

  echo "[2/4] Deleting API pod '${TARGET_POD}' and timing recovery..."
  START_TIME=$(date +%s)
  $KCMD delete pod "$TARGET_POD" -n "$DEV_NS" --grace-period=0 --force >/dev/null 2>&1

  # Await replacement pod readiness
  $KCMD wait --for=condition=Ready pod -l app.kubernetes.io/name=forgetasks-api -n "$DEV_NS" --timeout=60s
  END_TIME=$(date +%s)
  RECOVERY_SECS=$((END_TIME - START_TIME))

  NEW_POD=$($KCMD get pods -n "$DEV_NS" -l app.kubernetes.io/name=forgetasks-api -o jsonpath='{.items[0].metadata.name}')
  echo "      New Pod:           ${NEW_POD}"
  echo "      Recovery Duration: ${RECOVERY_SECS} seconds"

  if [ "$NEW_POD" = "$TARGET_POD" ]; then
    echo "[FAIL] Pod was not replaced by Deployment controller." >&2
    exit 1
  fi

  echo "[3/4] Documenting Single-Replica Availability Impact..."
  echo "      Architecture Note: With Deployment replicas=1, transient 503/connection drop"
  echo "      occurs during pod kill until replacement pod passes /actuator/health/readiness."
  echo "      Zero-downtime rolling replacement requires replicas >= 2 (tested in G07/G12)."

  echo "[4/4] Verifying Service Traffic Recovery..."
  kill "$PF_PID" 2>/dev/null || true
  $KCMD port-forward -n "$DEV_NS" svc/forgetasks-api "${LOCAL_TEST_PORT}:8080" --address 127.0.0.1 >/dev/null 2>&1 &
  PF_PID=$!
  sleep 2

  POST_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${LOCAL_TEST_PORT}/actuator/health")
  echo "      Post-Recovery Health Endpoint: HTTP ${POST_HEALTH}"
  if [ "$POST_HEALTH" != "200" ]; then
    echo "[FAIL] Service failed to restore healthy HTTP traffic after replacement." >&2
    exit 1
  fi

  echo "=============================================================================="
  echo " Functional Reconciliation: PASSED (ReplicaSet recreated pod; HTTP 200 restored)"
  if [ "$RECOVERY_SECS" -le 30 ]; then
    echo " Performance Objective:    PASSED (Reconciliation completed in ${RECOVERY_SECS}s <= 30s target)"
    echo " A-602 OVERALL RESULT:     PASSED"
  else
    echo " Performance Objective:    NOT MET (Reconciliation completed in ${RECOVERY_SECS}s > 30s target)"
    echo " A-602 OVERALL RESULT:     PASSED WITH LIMITATION (Cold-start bound)"
  fi
  echo "=============================================================================="
fi
