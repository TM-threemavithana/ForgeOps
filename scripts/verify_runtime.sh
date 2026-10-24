#!/usr/bin/env bash
set -e

mkdir -p /mnt/c/Project/ForgeOps/docs/evidence/G01
LOG=/mnt/c/Project/ForgeOps/docs/evidence/G01/runtime-curl-verification.log

echo "=== ForgeTasks Local Runtime Curl Verification ===" > "$LOG"
date >> "$LOG"
echo "" >> "$LOG"

echo "--- 1. Liveness Probe ---" >> "$LOG"
curl -s -i http://127.0.0.1:8080/actuator/health/liveness >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 2. Readiness Probe ---" >> "$LOG"
curl -s -i http://127.0.0.1:8080/actuator/health/readiness >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 3. Prometheus Metrics Scrape ---" >> "$LOG"
curl -s http://127.0.0.1:8080/actuator/prometheus | grep -E "^(jvm_memory_used_bytes|http_server_requests_seconds_count)" | head -n 10 >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 4. Account Registration ---" >> "$LOG"
curl -s -i -X POST http://127.0.0.1:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"lead_engineer","password":"SecurePassword123!"}' >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 5. Duplicate Account Registration (409 Conflict) ---" >> "$LOG"
curl -s -i -X POST http://127.0.0.1:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"lead_engineer","password":"SecurePassword123!"}' >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 6. Project Creation with ETag ---" >> "$LOG"
PROJ_RESP=$(curl -s -i -X POST http://127.0.0.1:8080/api/v1/projects \
  -u lead_engineer:SecurePassword123! \
  -H "Content-Type: application/json" \
  -d '{"name":"ForgeOps Core Platform","description":"Self-hosted local DevOps engineering lab"}')
echo "$PROJ_RESP" >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

PROJ_ID=$(echo "$PROJ_RESP" | grep -o '"id":"[^"]*' | head -n 1 | cut -d'"' -f4)
echo "Created Project ID: $PROJ_ID" >> "$LOG"

echo "--- 7. Mutating Project Without If-Match (428 Precondition Required) ---" >> "$LOG"
curl -s -i -X PATCH "http://127.0.0.1:8080/api/v1/projects/$PROJ_ID" \
  -u lead_engineer:SecurePassword123! \
  -H "Content-Type: application/json" \
  -d '{"name":"Mutated Without If-Match"}' >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 8. Mutating Project With Stale If-Match (412 Precondition Failed) ---" >> "$LOG"
curl -s -i -X PATCH "http://127.0.0.1:8080/api/v1/projects/$PROJ_ID" \
  -u lead_engineer:SecurePassword123! \
  -H 'If-Match: "5"' \
  -H "Content-Type: application/json" \
  -d '{"name":"Mutated With Stale If-Match"}' >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 9. Mutating Project With Matching If-Match (200 OK, New ETag) ---" >> "$LOG"
curl -s -i -X PATCH "http://127.0.0.1:8080/api/v1/projects/$PROJ_ID" \
  -u lead_engineer:SecurePassword123! \
  -H 'If-Match: "0"' \
  -H "Content-Type: application/json" \
  -d '{"name":"ForgeOps Core Platform v2"}' >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 10. Task Creation Under Project ---" >> "$LOG"
TASK_RESP=$(curl -s -i -X POST "http://127.0.0.1:8080/api/v1/projects/$PROJ_ID/tasks" \
  -u lead_engineer:SecurePassword123! \
  -H "Content-Type: application/json" \
  -d '{"title":"Implement G01 Spring Boot API","priority":"HIGH"}')
echo "$TASK_RESP" >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

TASK_ID=$(echo "$TASK_RESP" | grep -o '"id":"[^"]*' | head -n 1 | cut -d'"' -f4)

echo "--- 11. Retrieve Task with ETag ---" >> "$LOG"
curl -s -i -X GET "http://127.0.0.1:8080/api/v1/tasks/$TASK_ID" \
  -u lead_engineer:SecurePassword123! >> "$LOG"
echo "" >> "$LOG"
echo "" >> "$LOG"

echo "--- 12. Cross-Tenant Anti-Enumeration (404 Not Found) ---" >> "$LOG"
curl -s -i -X POST http://127.0.0.1:8080/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"unauthorized_user","password":"SecurePassword123!"}' > /dev/null

curl -s -i -X GET "http://127.0.0.1:8080/api/v1/projects/$PROJ_ID" \
  -u unauthorized_user:SecurePassword123! >> "$LOG"
echo "" >> "$LOG"
