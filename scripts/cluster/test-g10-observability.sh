#!/usr/bin/env bash
# ==============================================================================
# ForgeOps G10 Acceptance Verification Script
# Validates Loki, Alloy, Grafana Datasource, Correlation, RBAC, and PVC Invariants
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

# 2. Workload and Pod Health
info "Step 2: Verifying Pod health across namespaces"
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=60s
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=alloy --timeout=60s
kubectl wait --namespace forgeops-gitops-rehearsal --for=condition=ready pod -l app.kubernetes.io/name=forgetasks-rehearsal-api --timeout=60s
kubectl wait --namespace forgeops-gitops-rehearsal --for=condition=ready pod -l app.kubernetes.io/name=rehearsal-postgres --timeout=60s
pass "Loki, Alloy, Rehearsal API, and Rehearsal DB pods are all Ready."

# 3. Loki API & Storage Validation
info "Step 3: Checking Loki readiness and storage configuration"
LOKI_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}')
LOKI_READY=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- http://localhost:3100/ready)
if [[ "$LOKI_READY" != "ready" ]]; then
  fail "Loki /ready check failed: $LOKI_READY"
fi
pass "Loki /ready endpoint responded 'ready'."

# Check PVC capacity for Loki
LOKI_PVC_CAPACITY=$(kubectl get pvc loki-single-binary-0 -n forgeops-observability -o jsonpath='{.status.capacity.storage}')
if [[ "$LOKI_PVC_CAPACITY" != "2Gi" ]]; then
  fail "Expected Loki PVC capacity 2Gi, got $LOKI_PVC_CAPACITY"
fi
pass "Loki PVC capacity is verified at 2Gi (storage request boundary)."

# 4. Alloy Health Validation
info "Step 4: Checking Alloy health endpoint"
ALLOY_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=alloy -o jsonpath='{.items[0].metadata.name}')
ALLOY_HEALTHY=$(kubectl exec -n forgeops-observability "$ALLOY_POD" -- wget -q -O- http://localhost:12345/-/healthy)
if [[ "$ALLOY_HEALTHY" != "Alloy is healthy."* ]]; then
  fail "Alloy health check failed: $ALLOY_HEALTHY"
fi
pass "Alloy /-/healthy endpoint responded healthy."

# 5. Scoped RBAC Validation (Positive and Negative)
info "Step 5: Verifying RBAC boundaries for Alloy ServiceAccount"
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

# 6. Database Account Baseline Count
info "Step 6: Recording baseline accounts count from Rehearsal PostgreSQL"
PRE_COUNT=$(kubectl exec -n forgeops-gitops-rehearsal forgetasks-rehearsal-db-0 -- psql -U forgeuser -d forgetasks -t -A -c "SELECT count(*) FROM accounts;")
info "Baseline accounts count: $PRE_COUNT"

# 7. Execute Proven Invalid Account Registration POST Probe
info "Step 7: Executing G10-B proven invalid account registration POST probe"
TEST_CORRELATION_ID="req-g10-probe-$(date +%s)-$RANDOM"
info "Probe Correlation ID: $TEST_CORRELATION_ID"

# Forward port to rehearsal API temporarily
API_PORT=18080
kubectl port-forward -n forgeops-gitops-rehearsal svc/forgetasks-rehearsal-api "${API_PORT}:8080" > /dev/null 2>&1 &
PF_PID=$!
sleep 2

PROBE_OUTPUT_FILE=$(mktemp)
PROBE_HEADERS_FILE=$(mktemp)
trap 'rm -f "$PROBE_OUTPUT_FILE" "$PROBE_HEADERS_FILE"; kill -9 "$PF_PID" >/dev/null 2>&1 || true' EXIT

HTTP_STATUS=$(curl -s -o "$PROBE_OUTPUT_FILE" -D "$PROBE_HEADERS_FILE" -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: ${TEST_CORRELATION_ID}" \
  -d '{"username":"a","password":"123"}' \
  "http://127.0.0.1:${API_PORT}/api/v1/accounts")

# Verify HTTP 400 Bad Request
if [[ "$HTTP_STATUS" != "400" ]]; then
  fail "Expected HTTP 400 Bad Request, got $HTTP_STATUS"
fi
pass "Probe request returned HTTP 400 Bad Request."

# Verify response header X-Request-ID
if ! grep -iq "x-request-id: ${TEST_CORRELATION_ID}" "$PROBE_HEADERS_FILE"; then
  fail "HTTP response header X-Request-ID did not match probe correlation ID"
fi
pass "HTTP response header X-Request-ID matched probe correlation ID."

# Verify ProblemDetail correlationId in body
if ! grep -q "\"correlationId\":\"${TEST_CORRELATION_ID}\"" "$PROBE_OUTPUT_FILE"; then
  fail "ProblemDetail body does not contain correlationId: $TEST_CORRELATION_ID"
fi
pass "ProblemDetail body contained matching correlationId."

# Clean up port forward
kill -9 "$PF_PID" >/dev/null 2>&1 || true

# 8. Verify Database Unchanged
info "Step 8: Verifying Rehearsal database accounts count remained unchanged"
POST_COUNT=$(kubectl exec -n forgeops-gitops-rehearsal forgetasks-rehearsal-db-0 -- psql -U forgeuser -d forgetasks -t -A -c "SELECT count(*) FROM accounts;")
if [[ "$POST_COUNT" != "$PRE_COUNT" ]]; then
  fail "Database accounts count changed: pre=$PRE_COUNT, post=$POST_COUNT"
fi
pass "Database state completely unchanged ($POST_COUNT accounts). Zero records created."

# 9. Verify Loki Log Ingestion via LogQL
info "Step 9: Polling Loki for ingested ECS JSON log event with correlationId"
LOG_FOUND=false
for i in {1..20}; do
  QUERY_JSON=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
    --post-data="query={app=\"forgetasks-rehearsal-api\"} |= \"${TEST_CORRELATION_ID}\"" \
    http://localhost:3100/loki/api/v1/query 2>/dev/null || true)

  if echo "$QUERY_JSON" | grep -q "\"status\":\"success\""; then
    if echo "$QUERY_JSON" | grep -q "$TEST_CORRELATION_ID"; then
      LOG_FOUND=true
      break
    fi
  fi
  sleep 1
done

if [[ "$LOG_FOUND" != "true" ]]; then
  fail "Loki did not ingest the log event with correlationId $TEST_CORRELATION_ID within 20 seconds"
fi
pass "Log event with correlationId $TEST_CORRELATION_ID retrieved successfully from Loki via LogQL."

# Validate ECS JSON structure inside retrieved log
if ! echo "$QUERY_JSON" | grep -q "\"service\""; then
  fail "Retrieved log does not contain ECS service structure"
fi
if ! echo "$QUERY_JSON" | grep -q "\"ecs\""; then
  fail "Retrieved log does not contain ECS specification version structure"
fi
pass "Ingested log conforms to ECS structured JSON schema."

# 10. Low-Cardinality Index Labels Check
info "Step 10: Verifying Loki stream index labels"
LOKI_LABELS_JSON=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- http://localhost:3100/loki/api/v1/labels)
if ! echo "$LOKI_LABELS_JSON" | grep -q "\"status\":\"success\""; then
  fail "Failed to query Loki labels: $LOKI_LABELS_JSON"
fi

if echo "$LOKI_LABELS_JSON" | grep -E -q '(correlationId|X-Request-ID|timestamp|token|pod)'; then
  fail "Forbidden high-cardinality or dynamic label detected in Loki index: $LOKI_LABELS_JSON"
fi
pass "Loki index labels are strictly low-cardinality: $LOKI_LABELS_JSON."

# 11. Negative Log Isolation Validation (Validating Empty Result Arrays)
info "Step 11: Validating negative log isolation (empty result arrays)"
DEV_QUERY_JSON=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
  --post-data='query={namespace="forgeops-dev"}' \
  http://localhost:3100/loki/api/v1/query)

if ! echo "$DEV_QUERY_JSON" | grep -q "\"status\":\"success\""; then
  fail "Loki query failed for forgeops-dev negative check: $DEV_QUERY_JSON"
fi
if ! echo "$DEV_QUERY_JSON" | grep -q '"result":\[\]'; then
  fail "Forbidden logs from forgeops-dev detected in Loki! Result was not empty: $DEV_QUERY_JSON"
fi
pass "Negative Log Isolation: Exactly 0 logs from forgeops-dev in Loki (result: [])."

DB_QUERY_JSON=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
  --post-data='query={container="postgres"}' \
  http://localhost:3100/loki/api/v1/query)

if ! echo "$DB_QUERY_JSON" | grep -q "\"status\":\"success\""; then
  fail "Loki query failed for postgres negative check: $DB_QUERY_JSON"
fi
if ! echo "$DB_QUERY_JSON" | grep -q '"result":\[\]'; then
  fail "Forbidden logs from postgres container detected in Loki! Result was not empty: $DB_QUERY_JSON"
fi
pass "Negative Log Isolation: Exactly 0 logs from postgres container in Loki (result: [])."

# 12. Existing Grafana Loki Datasource Check (Runtime Credentials)
info "Step 12: Verifying existing Grafana Loki datasource via secure runtime credentials"
GRAFANA_USER=$(kubectl get secret g09-grafana-admin -n forgeops-observability -o jsonpath='{.data.admin-user}' | base64 -d)
GRAFANA_PASS=$(kubectl get secret g09-grafana-admin -n forgeops-observability -o jsonpath='{.data.admin-password}' | base64 -d)

GRAFANA_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
GRAFANA_DS_JSON=$(kubectl exec -n forgeops-observability "$GRAFANA_POD" -c grafana -- wget -q -O- \
  --user="$GRAFANA_USER" --password="$GRAFANA_PASS" \
  http://localhost:3000/api/datasources)

unset GRAFANA_USER GRAFANA_PASS

if ! echo "$GRAFANA_DS_JSON" | grep -q '"type":"loki"'; then
  fail "Grafana has not provisioned the Loki datasource"
fi
if ! echo "$GRAFANA_DS_JSON" | grep -q '"type":"prometheus"'; then
  fail "Existing Prometheus datasource is missing from Grafana!"
fi
pass "Grafana provisioned Loki datasource while preserving existing Prometheus datasource."

# 13. Prometheus Target Continuity Check
info "Step 13: Verifying Prometheus scrape targets remain UP"
PROM_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
PROM_TARGETS_JSON=$(kubectl exec -n forgeops-observability "$PROM_POD" -c prometheus -- wget -q -O- http://localhost:9090/api/v1/targets)

if echo "$PROM_TARGETS_JSON" | grep -q '"health":"down"'; then
  fail "One or more Prometheus targets are down: $PROM_TARGETS_JSON"
fi
pass "All existing Prometheus scrape targets remain UP and healthy."

# Cleanup temporary files
rm -f "$PROBE_OUTPUT_FILE" "$PROBE_HEADERS_FILE"
trap - EXIT

info "================================================================="
pass "ALL G10-C THROUGH G10-E ACCEPTANCE CRITERIA VERIFIED SUCCESSFULLY"
info "================================================================="
