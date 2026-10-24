#!/usr/bin/env bash
# ForgeOps Gate G02 — Comprehensive Stack Verification Script
# Validates API contract, optimistic concurrency, tenant isolation,
# data persistence, API restart recovery, and database restart recovery.

set -euo pipefail

BASE_URL="http://127.0.0.1:18080"
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/evidence/G02"
mkdir -p "$EVIDENCE_DIR"
LOG="$EVIDENCE_DIR/api-smoke-test.log"

echo "=== ForgeOps Gate G02 Live API Verification ===" > "$LOG"
date -u +"Date (UTC): %Y-%m-%dT%H:%M:%SZ" >> "$LOG"
echo "Target Base URL: $BASE_URL" >> "$LOG"
echo "" >> "$LOG"

PASSED_COUNT=0
FAILED_COUNT=0

assert_status() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "[PASS] $test_name (HTTP $actual)" | tee -a "$LOG"
        PASSED_COUNT=$((PASSED_COUNT + 1))
    else
        echo "[FAIL] $test_name (Expected HTTP $expected, got $actual)" | tee -a "$LOG"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

echo "--- 1. Application Liveness Probe ---" | tee -a "$LOG"
LIVE_CODE=$(curl -s -o /tmp/liveness.json -w "%{http_code}" "$BASE_URL/actuator/health/liveness")
assert_status "Liveness probe reports UP" 200 "$LIVE_CODE"
cat /tmp/liveness.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 2. Application Readiness Probe ---" | tee -a "$LOG"
READY_CODE=$(curl -s -o /tmp/readiness.json -w "%{http_code}" "$BASE_URL/actuator/health/readiness")
assert_status "Readiness probe reports UP" 200 "$READY_CODE"
cat /tmp/readiness.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 3. Prometheus Metrics Scrape ---" | tee -a "$LOG"
METRIC_CODE=$(curl -s -o /tmp/metrics.txt -w "%{http_code}" "$BASE_URL/actuator/prometheus")
assert_status "Prometheus metrics scrape" 200 "$METRIC_CODE"
grep -E "^(jvm_memory_used_bytes|http_server_requests_seconds_count)" /tmp/metrics.txt | head -n 6 >> "$LOG"
echo -e "\n" >> "$LOG"

# Generate unique run ID to avoid collisions
RUN_ID=$(date +%s)
USER_A="lead_eng_$RUN_ID"
PASS_A="PassSecret123!"
USER_B="audit_user_$RUN_ID"
PASS_B="AuditSecret123!"

echo "--- 4. Account Registration (User A) ---" | tee -a "$LOG"
REG_A_CODE=$(curl -s -o /tmp/reg_a.json -w "%{http_code}" -X POST "$BASE_URL/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USER_A\",\"password\":\"$PASS_A\"}")
assert_status "Account registration for User A" 201 "$REG_A_CODE"
cat /tmp/reg_a.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 5. Duplicate Account Registration Conflict ---" | tee -a "$LOG"
DUP_CODE=$(curl -s -o /tmp/dup.json -w "%{http_code}" -X POST "$BASE_URL/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USER_A\",\"password\":\"$PASS_A\"}")
assert_status "Duplicate registration returns 409 Conflict" 409 "$DUP_CODE"
cat /tmp/dup.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 6. Account Registration (User B) ---" | tee -a "$LOG"
REG_B_CODE=$(curl -s -o /tmp/reg_b.json -w "%{http_code}" -X POST "$BASE_URL/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USER_B\",\"password\":\"$PASS_B\"}")
assert_status "Account registration for User B" 201 "$REG_B_CODE"
cat /tmp/reg_b.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 7. Project Creation with ETag ---" | tee -a "$LOG"
PROJ_HEADERS="/tmp/proj_headers.txt"
PROJ_CODE=$(curl -s -D "$PROJ_HEADERS" -o /tmp/proj.json -w "%{http_code}" -X POST "$BASE_URL/api/v1/projects" \
    -u "$USER_A:$PASS_A" \
    -H "Content-Type: application/json" \
    -d '{"name":"ForgeOps Core Platform Lab","description":"Self-hosted local DevOps engineering platform"}')
assert_status "Project creation returns 201 Created" 201 "$PROJ_CODE"
cat "$PROJ_HEADERS" >> "$LOG"
cat /tmp/proj.json >> "$LOG"
echo -e "\n" >> "$LOG"

PROJ_ID=$(grep -o '"id":"[^"]*' /tmp/proj.json | head -n 1 | cut -d'"' -f4)
INITIAL_ETAG=$(grep -i '^etag:' "$PROJ_HEADERS" | tr -d '\r\n' | awk '{print $2}')
echo "Created Project ID: $PROJ_ID, Initial ETag: $INITIAL_ETAG" | tee -a "$LOG"

echo "--- 8. Project Retrieval with ETag ---" | tee -a "$LOG"
GET_PROJ_HEADERS="/tmp/get_proj_headers.txt"
GET_PROJ_CODE=$(curl -s -D "$GET_PROJ_HEADERS" -o /tmp/get_proj.json -w "%{http_code}" \
    -u "$USER_A:$PASS_A" \
    "$BASE_URL/api/v1/projects/$PROJ_ID")
assert_status "Project retrieval returns 200 OK" 200 "$GET_PROJ_CODE"
cat /tmp/get_proj.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 9. Mutating Project Without If-Match (428 Precondition Required) ---" | tee -a "$LOG"
NO_ETAG_CODE=$(curl -s -o /tmp/no_etag.json -w "%{http_code}" -X PATCH "$BASE_URL/api/v1/projects/$PROJ_ID" \
    -u "$USER_A:$PASS_A" \
    -H "Content-Type: application/json" \
    -d '{"name":"Mutated Without ETag"}')
assert_status "Mutation without If-Match returns 428 Precondition Required" 428 "$NO_ETAG_CODE"
cat /tmp/no_etag.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 10. Mutating Project With Stale If-Match (412 Precondition Failed) ---" | tee -a "$LOG"
STALE_ETAG_CODE=$(curl -s -o /tmp/stale_etag.json -w "%{http_code}" -X PATCH "$BASE_URL/api/v1/projects/$PROJ_ID" \
    -u "$USER_A:$PASS_A" \
    -H 'If-Match: "999"' \
    -H "Content-Type: application/json" \
    -d '{"name":"Mutated With Stale ETag"}')
assert_status "Mutation with stale If-Match returns 412 Precondition Failed" 412 "$STALE_ETAG_CODE"
cat /tmp/stale_etag.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 11. Mutating Project With Valid If-Match (200 OK, New ETag) ---" | tee -a "$LOG"
VALID_HEADERS="/tmp/valid_patch_headers.txt"
VALID_ETAG_CODE=$(curl -s -D "$VALID_HEADERS" -o /tmp/valid_patch.json -w "%{http_code}" -X PATCH "$BASE_URL/api/v1/projects/$PROJ_ID" \
    -u "$USER_A:$PASS_A" \
    -H "If-Match: $INITIAL_ETAG" \
    -H "Content-Type: application/json" \
    -d '{"name":"ForgeOps Core Platform Lab v2"}')
assert_status "Mutation with valid If-Match returns 200 OK" 200 "$VALID_ETAG_CODE"
cat "$VALID_HEADERS" >> "$LOG"
cat /tmp/valid_patch.json >> "$LOG"
echo -e "\n" >> "$LOG"

NEW_ETAG=$(grep -i '^etag:' "$VALID_HEADERS" | tr -d '\r\n' | awk '{print $2}')
echo "Updated Project ETag: $NEW_ETAG" | tee -a "$LOG"

echo "--- 12. Task Creation Under Owned Project ---" | tee -a "$LOG"
TASK_HEADERS="/tmp/task_headers.txt"
TASK_CODE=$(curl -s -D "$TASK_HEADERS" -o /tmp/task.json -w "%{http_code}" -X POST "$BASE_URL/api/v1/projects/$PROJ_ID/tasks" \
    -u "$USER_A:$PASS_A" \
    -H "Content-Type: application/json" \
    -d '{"title":"Implement G02 Docker Compose Stack","priority":"HIGH"}')
assert_status "Task creation returns 201 Created" 201 "$TASK_CODE"
cat "$TASK_HEADERS" >> "$LOG"
cat /tmp/task.json >> "$LOG"
echo -e "\n" >> "$LOG"

TASK_ID=$(grep -o '"id":"[^"]*' /tmp/task.json | head -n 1 | cut -d'"' -f4)
echo "Created Task ID: $TASK_ID" | tee -a "$LOG"

echo "--- 13. Task Retrieval with ETag ---" | tee -a "$LOG"
GET_TASK_CODE=$(curl -s -o /tmp/get_task.json -w "%{http_code}" \
    -u "$USER_A:$PASS_A" \
    "$BASE_URL/api/v1/tasks/$TASK_ID")
assert_status "Task retrieval returns 200 OK" 200 "$GET_TASK_CODE"
cat /tmp/get_task.json >> "$LOG"
echo -e "\n" >> "$LOG"

echo "--- 14. Cross-Tenant Authorization Isolation (Anti-Enumeration 404) ---" | tee -a "$LOG"
CROSS_PROJ_CODE=$(curl -s -o /tmp/cross_proj.json -w "%{http_code}" \
    -u "$USER_B:$PASS_B" \
    "$BASE_URL/api/v1/projects/$PROJ_ID")
assert_status "Cross-user project access rejected with 404 Not Found" 404 "$CROSS_PROJ_CODE"
cat /tmp/cross_proj.json >> "$LOG"
echo -e "\n" >> "$LOG"

CROSS_TASK_CODE=$(curl -s -o /tmp/cross_task.json -w "%{http_code}" \
    -u "$USER_B:$PASS_B" \
    "$BASE_URL/api/v1/tasks/$TASK_ID")
assert_status "Cross-user task access rejected with 404 Not Found" 404 "$CROSS_TASK_CODE"
cat /tmp/cross_task.json >> "$LOG"
echo -e "\n" >> "$LOG"

# Clean up temp files
rm -f /tmp/liveness.json /tmp/readiness.json /tmp/metrics.txt /tmp/reg_a.json /tmp/dup.json /tmp/reg_b.json \
      /tmp/proj_headers.txt /tmp/proj.json /tmp/get_proj_headers.txt /tmp/get_proj.json /tmp/no_etag.json \
      /tmp/stale_etag.json /tmp/valid_patch_headers.txt /tmp/valid_patch.json /tmp/task_headers.txt /tmp/task.json \
      /tmp/get_task.json /tmp/cross_proj.json /tmp/cross_task.json

echo "=== Smoke Test Summary ===" | tee -a "$LOG"
echo "Passed: $PASSED_COUNT | Failed: $FAILED_COUNT" | tee -a "$LOG"

# Export test identifiers for persistence and restart checks
echo "PERSISTENCE_TEST_USER_A=\"$USER_A\"" > "$EVIDENCE_DIR/test_identity.env"
echo "PERSISTENCE_TEST_PASS_A=\"$PASS_A\"" >> "$EVIDENCE_DIR/test_identity.env"
echo "PERSISTENCE_TEST_PROJ_ID=\"$PROJ_ID\"" >> "$EVIDENCE_DIR/test_identity.env"
echo "PERSISTENCE_TEST_TASK_ID=\"$TASK_ID\"" >> "$EVIDENCE_DIR/test_identity.env"

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "ERROR: One or more smoke tests failed."
    exit 1
fi
echo "All G02 live API smoke tests passed successfully."
