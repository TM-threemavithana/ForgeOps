#!/usr/bin/env bash
# ==============================================================================
# ForgeOps G10 Acceptance Verification Script
# Validates Loki, Alloy, Grafana Datasource, Correlation, RBAC, and PVC Invariants
# Uses robust host-side port-forwarding and structured JSON validation
# ==============================================================================
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-/home/tharuka/.kube/config-forgeops}"
export KUBECONFIG

EXPECTED_REHEARSAL_PVC_NAME="postgres-storage-forgetasks-rehearsal-db-0"
EXPECTED_REHEARSAL_PVC_UID="b5ea8ec9-47e8-4979-afdb-621f2e3c63b8"

EXPECTED_DEV_PVC_NAME="postgres-storage-forgetasks-db-0"
EXPECTED_DEV_PVC_UID="84853fb3-4d13-43a9-bc62-973c3be3c90c"

EXPECTED_OBS_PVC_NAME="prometheus-g09-monitoring-kube-promet-prometheus-db-prometheus-g09-monitoring-kube-promet-prometheus-0"
EXPECTED_OBS_PVC_UID="cd64e090-2c69-49b3-a389-de5841ce06d6"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

PIDS_TO_KILL=()
cleanup() {
  info "Cleaning up background port-forward processes and temporary artifacts..."
  for pid in "${PIDS_TO_KILL[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

info "Starting ForgeOps G10 Acceptance Verification"

# 1. Protected PVC UIDs Invariant Check
info "Step 1: Verifying protected PVC UIDs against documented baselines"
ACTUAL_REHEARSAL_UID=$(kubectl get pvc "$EXPECTED_REHEARSAL_PVC_NAME" -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}')
ACTUAL_DEV_UID=$(kubectl get pvc "$EXPECTED_DEV_PVC_NAME" -n forgeops-dev -o jsonpath='{.metadata.uid}')
ACTUAL_OBS_UID=$(kubectl get pvc "$EXPECTED_OBS_PVC_NAME" -n forgeops-observability -o jsonpath='{.metadata.uid}')

if [[ "$ACTUAL_REHEARSAL_UID" != "$EXPECTED_REHEARSAL_PVC_UID" ]]; then
  fail "Rehearsal PVC UID mismatch: expected $EXPECTED_REHEARSAL_PVC_UID, got $ACTUAL_REHEARSAL_UID"
fi
if [[ "$ACTUAL_DEV_UID" != "$EXPECTED_DEV_PVC_UID" ]]; then
  fail "Dev PVC UID mismatch: expected $EXPECTED_DEV_PVC_UID, got $ACTUAL_DEV_UID"
fi
if [[ "$ACTUAL_OBS_UID" != "$EXPECTED_OBS_PVC_UID" ]]; then
  fail "Observability PVC UID mismatch: expected $EXPECTED_OBS_PVC_UID, got $ACTUAL_OBS_UID"
fi
pass "All 3 protected PVC UIDs matched documented baselines identically."

# 2. Workload and Pod Health (Targeting exact names and verified labels)
info "Step 2: Verifying Pod health across namespaces"
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=60s
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=alloy --timeout=60s
kubectl wait --namespace forgeops-gitops-rehearsal --for=condition=ready pod -l app.kubernetes.io/name=rehearsal-api --timeout=60s
kubectl wait --namespace forgeops-gitops-rehearsal --for=condition=ready pod/forgetasks-rehearsal-db-0 --timeout=60s
pass "Loki, Alloy, Rehearsal API, and Rehearsal DB pods are all Ready."

# 3. Setup Localhost Port-Forwards for Host-Side Verification
info "Step 3: Establishing localhost port-forwards for reliable host-side testing"
LOKI_LOCAL_PORT=13100
ALLOY_LOCAL_PORT=12345
GRAFANA_LOCAL_PORT=13000
PROM_LOCAL_PORT=19090
API_LOCAL_PORT=18080

kubectl port-forward -n forgeops-observability svc/loki "${LOKI_LOCAL_PORT}:3100" >/dev/null 2>&1 &
PIDS_TO_KILL+=($!)

kubectl port-forward -n forgeops-observability svc/alloy "${ALLOY_LOCAL_PORT}:12345" >/dev/null 2>&1 &
PIDS_TO_KILL+=($!)

kubectl port-forward -n forgeops-observability svc/g09-monitoring-grafana "${GRAFANA_LOCAL_PORT}:80" >/dev/null 2>&1 &
PIDS_TO_KILL+=($!)

kubectl port-forward -n forgeops-observability svc/g09-monitoring-kube-promet-prometheus "${PROM_LOCAL_PORT}:9090" >/dev/null 2>&1 &
PIDS_TO_KILL+=($!)

kubectl port-forward -n forgeops-gitops-rehearsal svc/forgetasks-rehearsal-api "${API_LOCAL_PORT}:8080" >/dev/null 2>&1 &
PIDS_TO_KILL+=($!)

sleep 3
pass "Port-forward connections established on 127.0.0.1."

# 4. Loki Readiness and Storage Capacity Check
info "Step 4: Checking Loki /ready endpoint and PVC capacity via host-side curl"
LOKI_READY_RESP=$(curl -s -w "\n%{http_code}" "http://127.0.0.1:${LOKI_LOCAL_PORT}/ready")
LOKI_STATUS=$(echo "$LOKI_READY_RESP" | tail -n 1)
LOKI_BODY=$(echo "$LOKI_READY_RESP" | sed '$d')

if [[ "$LOKI_STATUS" != "200" ]] || [[ "$LOKI_BODY" != "ready" ]]; then
  fail "Loki /ready check failed: HTTP $LOKI_STATUS, body: $LOKI_BODY"
fi
pass "Loki /ready responded 200 OK ('ready')."

LOKI_PVC_CAPACITY=$(kubectl get pvc loki-single-binary-0 -n forgeops-observability -o jsonpath='{.status.capacity.storage}')
if [[ "$LOKI_PVC_CAPACITY" != "2Gi" ]]; then
  fail "Expected Loki PVC capacity 2Gi, got $LOKI_PVC_CAPACITY"
fi
pass "Loki PVC capacity verified at 2Gi (storage request boundary)."

# 5. Alloy Health Check
info "Step 5: Checking Alloy /-/healthy endpoint via host-side curl"
ALLOY_HEALTH_RESP=$(curl -s -w "\n%{http_code}" "http://127.0.0.1:${ALLOY_LOCAL_PORT}/-/healthy")
ALLOY_STATUS=$(echo "$ALLOY_HEALTH_RESP" | tail -n 1)
ALLOY_BODY=$(echo "$ALLOY_HEALTH_RESP" | sed '$d')

if [[ "$ALLOY_STATUS" != "200" ]] || [[ "$ALLOY_BODY" != "Alloy is healthy."* ]]; then
  fail "Alloy health check failed: HTTP $ALLOY_STATUS, body: $ALLOY_BODY"
fi
pass "Alloy /-/healthy responded 200 OK ('Alloy is healthy.')."

# 6. Scoped RBAC Validation (Positive and Negative)
info "Step 6: Verifying RBAC boundaries for Alloy ServiceAccount"
AUTH_REHEARSAL=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-gitops-rehearsal)
if [[ "$AUTH_REHEARSAL" != "yes" ]]; then
  fail "Alloy SA should be allowed to get pods in forgeops-gitops-rehearsal, got $AUTH_REHEARSAL"
fi
pass "Positive RBAC: Alloy SA can get pods in forgeops-gitops-rehearsal."

AUTH_DEV=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-dev 2>&1 || true)
if [[ "$AUTH_DEV" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get pods in forgeops-dev, got $AUTH_DEV"
fi
pass "Negative RBAC: Alloy SA denied pod access in forgeops-dev."

AUTH_SECRET=$(kubectl auth can-i get secrets --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-gitops-rehearsal 2>&1 || true)
if [[ "$AUTH_SECRET" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get secrets in rehearsal, got $AUTH_SECRET"
fi
pass "Negative RBAC: Alloy SA denied secret access."

AUTH_KSYS=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n kube-system 2>&1 || true)
if [[ "$AUTH_KSYS" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get pods in kube-system, got $AUTH_KSYS"
fi
pass "Negative RBAC: Alloy SA denied pod access in kube-system."

# 7. Record Baseline Account Count
info "Step 7: Recording baseline accounts count from Rehearsal PostgreSQL"
PRE_COUNT=$(kubectl exec -n forgeops-gitops-rehearsal forgetasks-rehearsal-db-0 -- psql -U forgeuser -d forgetasks -t -A -c "SELECT count(*) FROM accounts;")
info "Baseline accounts count: $PRE_COUNT"

# 8. Execute Proven G10-B Invalid Registration Probe
info "Step 8: Executing proven G10-B invalid account registration POST probe"
TEST_CORRELATION_ID="req-g10-probe-$(date +%s)-$RANDOM"
info "Probe Correlation ID: $TEST_CORRELATION_ID"

PROBE_HEADERS_FILE=$(mktemp)
PROBE_BODY_FILE=$(mktemp)

HTTP_STATUS=$(curl -s -o "$PROBE_BODY_FILE" -D "$PROBE_HEADERS_FILE" -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: ${TEST_CORRELATION_ID}" \
  -d '{"username":"a","password":"123"}' \
  "http://127.0.0.1:${API_LOCAL_PORT}/api/v1/accounts")

if [[ "$HTTP_STATUS" != "400" ]]; then
  fail "Expected HTTP 400 Bad Request, got $HTTP_STATUS"
fi
pass "Probe request returned HTTP 400 Bad Request."

if ! grep -iq "x-request-id: ${TEST_CORRELATION_ID}" "$PROBE_HEADERS_FILE"; then
  fail "HTTP response header X-Request-ID did not match probe correlation ID"
fi
pass "HTTP response header X-Request-ID matched probe correlation ID."

python3 -c "
import sys, json
with open('$PROBE_BODY_FILE') as f:
    data = json.load(f)
assert data.get('correlationId') == '$TEST_CORRELATION_ID', 'Body correlationId mismatch'
"
pass "ProblemDetail body contained matching correlationId."
rm -f "$PROBE_HEADERS_FILE" "$PROBE_BODY_FILE"

# 9. Verify Database Account Count Unchanged
info "Step 9: Verifying Rehearsal database accounts count remained unchanged"
POST_COUNT=$(kubectl exec -n forgeops-gitops-rehearsal forgetasks-rehearsal-db-0 -- psql -U forgeuser -d forgetasks -t -A -c "SELECT count(*) FROM accounts;")
if [[ "$POST_COUNT" != "$PRE_COUNT" ]]; then
  fail "Database accounts count changed: pre=$PRE_COUNT, post=$POST_COUNT"
fi
pass "Database state completely unchanged ($POST_COUNT accounts). Zero records created."

# 10. Robust LogQL Ingestion Polling & ECS JSON Parsing
info "Step 10: Polling Loki for ingested ECS JSON log event with correlationId"
LOG_FOUND=false
for i in {1..20}; do
  LOKI_QUERY_RESP=$(curl -s -G "http://127.0.0.1:${LOKI_LOCAL_PORT}/loki/api/v1/query" \
    --data-urlencode "query={app=\"rehearsal-api\"} |= \"${TEST_CORRELATION_ID}\"")

  IS_VALID=$(echo "$LOKI_QUERY_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if d.get('status') == 'success':
        results = d.get('data', {}).get('result', [])
        found = False
        for stream in results:
            for entry in stream.get('values', []):
                log_line = entry[1]
                if '$TEST_CORRELATION_ID' in log_line:
                    parsed = json.loads(log_line)
                    assert parsed.get('correlationId') == '$TEST_CORRELATION_ID'
                    assert 'service' in parsed and 'ecs' in parsed
                    found = True
                    break
            if found:
                break
        print('true' if found else 'false')
    else:
        print('false')
except Exception:
    print('false')
" 2>/dev/null || echo "false")

  if [[ "$IS_VALID" == "true" ]]; then
    LOG_FOUND=true
    break
  fi
  sleep 1
done

if [[ "$LOG_FOUND" != "true" ]]; then
  fail "Loki did not ingest the log event with correlationId $TEST_CORRELATION_ID within 20 seconds"
fi
pass "Log event with correlationId $TEST_CORRELATION_ID retrieved from Loki via LogQL and verified against ECS JSON schema."

# 11. Low-Cardinality Index Labels Check
info "Step 11: Verifying Loki stream index labels"
LOKI_LABELS_JSON=$(curl -s "http://127.0.0.1:${LOKI_LOCAL_PORT}/loki/api/v1/labels")
python3 -c "
import sys, json
d = json.loads('''$LOKI_LABELS_JSON''')
assert d.get('status') == 'success', 'Failed to retrieve labels'
labels = set(d.get('data', []))
forbidden = {'correlationId', 'X-Request-ID', 'timestamp', 'token', 'pod'}
overlap = labels.intersection(forbidden)
assert not overlap, f'Forbidden high-cardinality labels found: {overlap}'
assert {'app', 'container', 'namespace'}.issubset(labels) or 'app' in labels, f'Expected labels missing: {labels}'
"
pass "Loki index labels are strictly low-cardinality and exclude dynamic Pod names."

# 12. Negative Log Isolation Validation (Validating Empty Result Arrays)
info "Step 12: Validating negative log isolation (empty result arrays)"
DEV_QUERY_RESP=$(curl -s -G "http://127.0.0.1:${LOKI_LOCAL_PORT}/loki/api/v1/query" \
  --data-urlencode 'query={namespace="forgeops-dev"}')

echo "$DEV_QUERY_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('status') == 'success', 'Loki query returned non-success status'
results = d.get('data', {}).get('result', [])
assert len(results) == 0, f'Forbidden logs from forgeops-dev detected: count={len(results)}'
"
pass "Negative Log Isolation: Exactly 0 logs from forgeops-dev in Loki (result: [])."

DB_QUERY_RESP=$(curl -s -G "http://127.0.0.1:${LOKI_LOCAL_PORT}/loki/api/v1/query" \
  --data-urlencode 'query={container="postgres"}')

echo "$DB_QUERY_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('status') == 'success', 'Loki query returned non-success status'
results = d.get('data', {}).get('result', [])
assert len(results) == 0, f'Forbidden logs from postgres container detected: count={len(results)}'
"
pass "Negative Log Isolation: Exactly 0 logs from postgres container in Loki (result: [])."

# 13. Existing Grafana Loki Datasource Check (Runtime Credentials)
info "Step 13: Verifying Grafana Loki datasource provisioning via host-side curl"
GRAFANA_USER=$(kubectl get secret g09-grafana-admin -n forgeops-observability -o jsonpath='{.data.admin-user}' | base64 -d)
GRAFANA_PASS=$(kubectl get secret g09-grafana-admin -n forgeops-observability -o jsonpath='{.data.admin-password}' | base64 -d)

GRAFANA_DS_RESP=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/datasources")
unset GRAFANA_USER GRAFANA_PASS

echo "$GRAFANA_DS_RESP" | python3 -c "
import sys, json
datasources = json.load(sys.stdin)
assert isinstance(datasources, list), 'Expected datasources array'
types = {ds.get('type'): ds.get('url') for ds in datasources}
assert 'loki' in types, 'Loki datasource missing in Grafana'
assert 'prometheus' in types, 'Prometheus datasource missing in Grafana'
assert types['loki'] == 'http://loki.forgeops-observability.svc.cluster.local:3100', f'Loki URL mismatch: {types[\"loki\"]}'
"
pass "Grafana provisioned Loki datasource while preserving existing Prometheus datasource."

# 14. Prometheus Target Continuity Check
info "Step 14: Verifying Prometheus scrape targets remain UP via host-side curl"
PROM_TARGETS_RESP=$(curl -s "http://127.0.0.1:${PROM_LOCAL_PORT}/api/v1/targets")
echo "$PROM_TARGETS_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
assert data.get('status') == 'success', 'Prometheus targets API returned non-success'
active_targets = data.get('data', {}).get('activeTargets', [])
down_targets = [t.get('labels', {}).get('job') for t in active_targets if t.get('health') != 'up']
assert len(down_targets) == 0, f'Prometheus targets down: {down_targets}'
"
pass "All existing Prometheus scrape targets remain UP and healthy."

info "================================================================="
pass "ALL G10-C THROUGH G10-E ACCEPTANCE CRITERIA VERIFIED SUCCESSFULLY"
info "================================================================="
