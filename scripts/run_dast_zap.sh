#!/usr/bin/env bash
# ForgeOps Gate G09.3: OWASP ZAP Baseline DAST Scanning Runner
# Runs an isolated, passive dynamic application security scan against an ephemeral ForgeTasks API container.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES_FILE="${REPO_ROOT}/security/dast/zap/zap-rules.conf"
REPORTS_DIR="${REPO_ROOT}/target/zap-reports"
ZAP_IMAGE="ghcr.io/zaproxy/zaproxy:2.16.0@sha256:391f66efa53b30de40d4a1c6e28146477263552fc828bc7613c9cd11a2949908"

echo "=== ForgeOps OWASP ZAP DAST Baseline Scan ==="

# Check Docker daemon availability
if ! docker info >/dev/null 2>&1; then
    echo "[WARN] Docker daemon is not accessible in this environment."
    echo "       Local DAST execution requires Docker to host the ephemeral test target and ZAP scanner."
    echo "       In CI (GitHub Actions), Docker runs natively under the 'dast-zap-scan' job."
    echo "       To run locally, start Docker Desktop and re-run this script."
    exit 0
fi

mkdir -p "${REPORTS_DIR}"
chmod 777 "${REPORTS_DIR}" 2>/dev/null || true

RUN_ID="$(date +%s)"
NETWORK_NAME="zap-net-${RUN_ID}"
DB_CONTAINER="zap-db-${RUN_ID}"
APP_CONTAINER="zap-app-${RUN_ID}"

cleanup() {
    echo "--> Cleaning up ephemeral DAST containers and networks..."
    docker rm -f "${APP_CONTAINER}" >/dev/null 2>&1 || true
    docker rm -f "${DB_CONTAINER}" >/dev/null 2>&1 || true
    docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
    echo "  [PASS] Ephemeral test infrastructure successfully decommissioned."
}
trap cleanup EXIT

# 1. Create isolated Docker bridge network
echo "--> Creating isolated Docker bridge network: ${NETWORK_NAME}..."
docker network create "${NETWORK_NAME}"

# 2. Launch ephemeral PostgreSQL container
echo "--> Starting ephemeral test database: ${DB_CONTAINER}..."
docker run -d --name "${DB_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    -e POSTGRES_DB=forgetasks_test \
    -e POSTGRES_USER=forge_test \
    -e POSTGRES_PASSWORD=forge_test_secret \
    postgres:16-alpine

# Wait for postgres
echo "--> Waiting for PostgreSQL readiness..."
for i in {1..30}; do
    if docker exec "${DB_CONTAINER}" pg_isready -U forge_test >/dev/null 2>&1; then
        echo "  [PASS] PostgreSQL is ready."
        break
    fi
    sleep 1
done

# 3. Build & run ephemeral ForgeTasks API container
echo "--> Building ephemeral ForgeTasks API test image..."
docker build -t "forgetasks-api:dast-test" "${REPO_ROOT}/apps/forgetasks-api"

echo "--> Launching ephemeral API container: ${APP_CONTAINER}..."
docker run -d --name "${APP_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    -e SPRING_PROFILES_ACTIVE=dev \
    -e SPRING_DATASOURCE_URL="jdbc:postgresql://${DB_CONTAINER}:5432/forgetasks_test" \
    -e SPRING_DATASOURCE_USERNAME=forge_test \
    -e SPRING_DATASOURCE_PASSWORD=forge_test_secret \
    -e PORT=8080 \
    -e MANAGEMENT_PORT=8080 \
    "forgetasks-api:dast-test"

# Wait for application health probe
echo "--> Waiting for ForgeTasks API health probe (/actuator/health)..."
for i in {1..60}; do
    if docker run --rm --network "${NETWORK_NAME}" curlimages/curl:8.10.1 -s http://${APP_CONTAINER}:8080/actuator/health | grep -q "UP"; then
        echo "  [PASS] ForgeTasks API is UP and healthy."
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "[FAIL] ForgeTasks API failed to start within timeout."
        docker logs "${APP_CONTAINER}"
        exit 1
    fi
done

# 4. Execute OWASP ZAP Baseline Scan
echo "--> Executing OWASP ZAP baseline scan against http://${APP_CONTAINER}:8080..."
set +e
docker run --rm \
    --network "${NETWORK_NAME}" \
    -v "${REPORTS_DIR}:/zap/wrk/:rw" \
    -v "${RULES_FILE}:/zap/rules.conf:ro" \
    "${ZAP_IMAGE}" \
    zap-baseline.py \
    -t "http://${APP_CONTAINER}:8080" \
    -c /zap/rules.conf \
    -r report.html \
    -J report.json \
    -w report.md \
    -I
ZAP_EXIT_CODE=$?
set -e

echo "  ZAP baseline completed with exit code: ${ZAP_EXIT_CODE}"

# 5. Evaluate Report & Enforce Risk Thresholds
REPORT_FILE="${REPORTS_DIR}/report.json"
if [ ! -f "${REPORT_FILE}" ]; then
    echo "[FAIL] ZAP did not produce expected report.json."
    exit 1
fi

echo "--> Analyzing ZAP DAST findings from ${REPORT_FILE}..."
python3 -c "
import json, sys

with open('${REPORT_FILE}', 'r', encoding='utf-8') as f:
    data = json.load(f)

site_list = data.get('site', [])
high_count = 0
medium_count = 0
low_count = 0
info_count = 0

for site in site_list:
    for alert in site.get('alerts', []):
        risk = alert.get('riskdesc', '')
        if 'High' in risk:
            high_count += 1
            print(f'  [HIGH] {alert.get(\"name\")}')
        elif 'Medium' in risk:
            medium_count += 1
            print(f'  [MEDIUM] {alert.get(\"name\")}')
        elif 'Low' in risk:
            low_count += 1
        elif 'Informational' in risk:
            info_count += 1

print(f'Findings Summary: High={high_count}, Medium={medium_count}, Low={low_count}, Info={info_count}')

if high_count > 0 or medium_count > 0:
    print(f'[FAIL] Security gate violation: {high_count} HIGH and {medium_count} MEDIUM alerts detected.')
    sys.exit(1)
else:
    print('[PASS] Zero HIGH and zero MEDIUM security alerts detected. DAST gate passed.')
"

echo "================================================="
echo " OWASP ZAP DAST baseline scan completed cleanly! "
echo " Reports available at: ${REPORTS_DIR}            "
echo "================================================="
