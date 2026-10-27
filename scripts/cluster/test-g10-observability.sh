#!/usr/bin/env bash
# ==============================================================================
# ForgeOps G10 Acceptance Verification Script
# Validates Loki, Alloy, Grafana Datasource, Correlation, RBAC, and PVC Invariants
# ==============================================================================
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-/home/tharuka/.kube/config-forgeops}"
export KUBECONFIG

EXPECTED_REHEARSAL_PVC_UID="b5ea8ec9-47e8-4979-afdb-621f2e3c63b8"
EXPECTED_DEV_PVC_UID="84853fb3-4d13-43a9-bc62-973c3be3c90c"
EXPECTED_OBSERVABILITY_PVC_UID="cd64e090-2c69-49b3-a389-de5841ce06d6"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

info "Starting ForgeOps G10 Acceptance Verification"

# 1. Protected PVC UIDs Invariant Check
info "Step 1: Verifying protected PVC UIDs"
ACTUAL_REHEARSAL_UID=$(kubectl get pvc data-forgetasks-rehearsal-db-0 -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}')
ACTUAL_DEV_UID=$(kubectl get pvc data-forgetasks-dev-db-0 -n forgeops-dev -o jsonpath='{.metadata.uid}')
ACTUAL_OBS_UID=$(kubectl get pvc -n forgeops-observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.uid}')

if [[ "$ACTUAL_REHEARSAL_UID" != "$EXPECTED_REHEARSAL_PVC_UID" ]]; then
  fail "Rehearsal PVC UID mismatch: expected $EXPECTED_REHEARSAL_PVC_UID, got $ACTUAL_REHEARSAL_UID"
fi
if [[ "$ACTUAL_DEV_UID" != "$EXPECTED_DEV_PVC_UID" ]]; then
  fail "Dev PVC UID mismatch: expected $EXPECTED_DEV_PVC_UID, got $ACTUAL_DEV_UID"
fi
if [[ "$ACTUAL_OBS_UID" != "$EXPECTED_OBSERVABILITY_PVC_UID" ]]; then
  fail "Observability PVC UID mismatch: expected $EXPECTED_OBSERVABILITY_PVC_UID, got $ACTUAL_OBS_UID"
fi
pass "All 3 protected PVC UIDs preserved identically."

# 2. Workload and Pod Health
info "Step 2: Verifying Pod health across namespaces"
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=loki --timeout=60s
kubectl wait --namespace forgeops-observability --for=condition=ready pod -l app.kubernetes.io/name=alloy --timeout=60s
kubectl wait --namespace forgeops-gitops-rehearsal --for=condition=ready pod -l app.kubernetes.io/name=forgetasks-rehearsal-api --timeout=60s
pass "Loki, Alloy, and Rehearsal API pods are Ready."

# 3. Loki API & Storage Validation
info "Step 3: Checking Loki readiness and storage configuration"
LOKI_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}')
LOKI_READY=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- http://localhost:3100/ready || true)
if [[ "$LOKI_READY" != "ready" ]]; then
  fail "Loki is not ready: $LOKI_READY"
fi
pass "Loki /ready endpoint responded 'ready'."

# Check PVC size for Loki
LOKI_PVC_CAPACITY=$(kubectl get pvc loki-single-binary-0 -n forgeops-observability -o jsonpath='{.status.capacity.storage}')
if [[ "$LOKI_PVC_CAPACITY" != "2Gi" ]]; then
  fail "Expected Loki PVC capacity 2Gi, got $LOKI_PVC_CAPACITY"
fi
pass "Loki PVC is bounded at 2Gi."

# 4. Alloy Health Validation
info "Step 4: Checking Alloy health endpoint"
ALLOY_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=alloy -o jsonpath='{.items[0].metadata.name}')
ALLOY_HEALTHY=$(kubectl exec -n forgeops-observability "$ALLOY_POD" -- wget -q -O- http://localhost:12345/-/healthy || true)
if [[ "$ALLOY_HEALTHY" != "Alloy is healthy."* ]]; then
  fail "Alloy health check failed: $ALLOY_HEALTHY"
fi
pass "Alloy /-/healthy endpoint responded healthy."

# 5. Scoped RBAC Validation (Positive and Negative)
info "Step 5: Verifying RBAC boundaries for Alloy ServiceAccount"
# Positive test: Alloy CAN list pods in forgeops-gitops-rehearsal
AUTH_REHEARSAL=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-gitops-rehearsal)
if [[ "$AUTH_REHEARSAL" != "yes" ]]; then
  fail "Alloy SA should be allowed to get pods in forgeops-gitops-rehearsal, got $AUTH_REHEARSAL"
fi
pass "Positive RBAC: Alloy SA can get pods in forgeops-gitops-rehearsal."

# Negative test 1: Alloy CANNOT get pods in forgeops-dev
AUTH_DEV=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-dev 2>&1 || true)
if [[ "$AUTH_DEV" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get pods in forgeops-dev, got $AUTH_DEV"
fi
pass "Negative RBAC: Alloy SA denied pod access in forgeops-dev."

# Negative test 2: Alloy CANNOT get secrets anywhere
AUTH_SECRET=$(kubectl auth can-i get secrets --as=system:serviceaccount:forgeops-observability:alloy -n forgeops-gitops-rehearsal 2>&1 || true)
if [[ "$AUTH_SECRET" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get secrets in rehearsal, got $AUTH_SECRET"
fi
pass "Negative RBAC: Alloy SA denied secret access."

# Negative test 3: Alloy CANNOT get pods in kube-system
AUTH_KSYS=$(kubectl auth can-i get pods --as=system:serviceaccount:forgeops-observability:alloy -n kube-system 2>&1 || true)
if [[ "$AUTH_KSYS" != "no" ]]; then
  fail "Negative RBAC failed: Alloy SA must NOT get pods in kube-system, got $AUTH_KSYS"
fi
pass "Negative RBAC: Alloy SA denied pod access in kube-system."

# 6. End-to-End Correlation Request & Ingestion Test
info "Step 6: Executing safe HTTP request with X-Request-ID and verifying end-to-end correlation"
TEST_CORRELATION_ID="g10-test-$(cat /proc/sys/kernel/random/uuid)"
info "Probe Correlation ID: $TEST_CORRELATION_ID"

# Forward port to rehearsal API temporarily
API_PORT=18080
kubectl port-forward -n forgeops-gitops-rehearsal svc/forgetasks-rehearsal-api "${API_PORT}:8080" > /dev/null 2>&1 &
PF_PID=$!
trap "kill -9 $PF_PID >/dev/null 2>&1 || true" EXIT
sleep 2

# Execute safe probe request (deterministic 404 for non-existent UUID)
PROBE_RESP=$(curl -s -i -H "X-Request-ID: ${TEST_CORRELATION_ID}" "http://127.0.0.1:${API_PORT}/api/v1/tasks/00000000-0000-0000-0000-000000000000")

# Verify HTTP response header
if ! echo "$PROBE_RESP" | grep -iq "x-request-id: ${TEST_CORRELATION_ID}"; then
  fail "HTTP response header X-Request-ID did not match probe ID"
fi
pass "HTTP response header X-Request-ID matched probe ID."

# Verify ProblemDetail body correlationId
if ! echo "$PROBE_RESP" | grep -q "\"correlationId\":\"${TEST_CORRELATION_ID}\""; then
  fail "HTTP response body does not contain correlationId: $TEST_CORRELATION_ID"
fi
pass "HTTP ProblemDetail body contained matching correlationId."

# Kill port forward
kill -9 $PF_PID >/dev/null 2>&1 || true
trap - EXIT

# Give Alloy and Loki up to 15 seconds to ingest the log
info "Waiting for log event to be ingested into Loki..."
LOG_FOUND=false
for i in {1..15}; do
  QUERY_RESULT=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
    --post-data="query={app=\"forgetasks-rehearsal-api\"} |= \"${TEST_CORRELATION_ID}\"" \
    http://localhost:3100/loki/api/v1/query || true)

  if echo "$QUERY_RESULT" | grep -q "$TEST_CORRELATION_ID"; then
    LOG_FOUND=true
    break
  fi
  sleep 1
done

if [[ "$LOG_FOUND" != "true" ]]; then
  fail "Loki did not ingest the log event with correlationId $TEST_CORRELATION_ID within 15 seconds"
fi
pass "Log event with correlationId $TEST_CORRELATION_ID successfully retrieved from Loki via LogQL."

# 7. Low-Cardinality Labels Verification
info "Step 7: Verifying Loki stream index labels"
LOKI_LABELS=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- http://localhost:3100/loki/api/v1/labels || true)
if echo "$LOKI_LABELS" | grep -E -q '(correlationId|X-Request-ID|timestamp|token)'; then
  fail "High-cardinality label detected in Loki index: $LOKI_LABELS"
fi
pass "Loki index labels are strictly low-cardinality: $LOKI_LABELS."

# 8. Negative Namespace & Container Log Scrape Verification
info "Step 8: Verifying no logs ingested from forbidden namespaces or containers"
DEV_LOGS=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
  --post-data='query={namespace="forgeops-dev"}' \
  http://localhost:3100/loki/api/v1/query || true)

if echo "$DEV_LOGS" | grep -q '"values":\[\['; then
  fail "Forbidden logs from forgeops-dev detected in Loki!"
fi
pass "Negative Log Scope: Zero logs from forgeops-dev in Loki."

DB_LOGS=$(kubectl exec -n forgeops-observability "$LOKI_POD" -- wget -q -O- \
  --post-data='query={container="postgres"}' \
  http://localhost:3100/loki/api/v1/query || true)

if echo "$DB_LOGS" | grep -q '"values":\[\['; then
  fail "Forbidden logs from postgres container detected in Loki!"
fi
pass "Negative Log Scope: Zero logs from postgres database container in Loki."

# 9. Existing Grafana Datasource Verification
info "Step 9: Verifying Grafana Loki datasource registration"
GRAFANA_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
GRAFANA_DS=$(kubectl exec -n forgeops-observability "$GRAFANA_POD" -c grafana -- wget -q -O- --header="Authorization: Basic YWRtaW46cHJvbS1vcGVyYXRvcg==" http://localhost:3000/api/datasources || true)

if ! echo "$GRAFANA_DS" | grep -q '"type":"loki"'; then
  fail "Grafana has not provisioned the Loki datasource"
fi
pass "Existing G09 Grafana successfully provisioned Loki datasource."

# 10. Prometheus Target Health Check
info "Step 10: Verifying Prometheus scrape targets remain UP"
PROM_POD=$(kubectl get pod -n forgeops-observability -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
PROM_TARGETS=$(kubectl exec -n forgeops-observability "$PROM_POD" -c prometheus -- wget -q -O- http://localhost:9090/api/v1/targets || true)

UNHEALTHY_TARGETS=$(echo "$PROM_TARGETS" | grep -o '"health":"down"' || true)
if [[ -n "$UNHEALTHY_TARGETS" ]]; then
  fail "One or more Prometheus targets are down: $UNHEALTHY_TARGETS"
fi
pass "All existing Prometheus scrape targets remain healthy (UP)."

info "================================================================="
pass "ALL G10-C THROUGH G10-E ACCEPTANCE CRITERIA VERIFIED SUCCESSFULLY"
info "================================================================="
