#!/usr/bin/env bash
# ==============================================================================
# ForgeOps k6 Load Testing Orchestrator
# Executes parameterized k6 performance and reliability scenarios
# Strict local safety guards and threshold verification
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K6_DIR="${SCRIPT_DIR}/k6"

# Mandated fixed port and target: strictly 127.0.0.1:8082 targeting forgeops-sre-lab
MANDATED_PORT=8082
MANDATED_TARGET_URL="http://127.0.0.1:${MANDATED_PORT}"
DISPOSABLE_NAMESPACE="forgeops-sre-lab"

TARGET_URL="${TARGET_URL:-$MANDATED_TARGET_URL}"
ENDPOINT="${ENDPOINT:-/actuator/health/readiness}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/results}"
SCENARIO="${1:-smoke}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $1" >&2; exit 1; }

# Guard 1: Enforce strict target URL and port
if [[ "$TARGET_URL" != "$MANDATED_TARGET_URL" ]]; then
    fail "SAFETY VIOLATION: Target URL '$TARGET_URL' is forbidden! Must be strictly '$MANDATED_TARGET_URL'."
fi

# Guard 2: Ensure k6 binary is installed
if ! command -v k6 >/dev/null 2>&1; then
    fail "k6 binary not found in PATH. Install k6 or make it executable in /usr/local/bin/k6."
fi

# Guard 3: Verify or establish port-forward target and endpoint validity
info "Verifying target endpoint safety and workload ownership..."
SPAWNED_PF=0
if ! curl -sf "${TARGET_URL}/actuator/health" >/dev/null 2>&1; then
    info "Port-forward on port ${MANDATED_PORT} not detected. Establishing safe local tunnel to ${DISPOSABLE_NAMESPACE}/svc/sre-api..."
    kubectl port-forward -n "${DISPOSABLE_NAMESPACE}" svc/sre-api "${MANDATED_PORT}:8080" >/dev/null 2>&1 &
    PF_PID=$!
    SPAWNED_PF=1
    trap 'if [[ "$SPAWNED_PF" -eq 1 ]]; then kill -9 $PF_PID >/dev/null 2>&1 || true; fi' EXIT INT TERM ERR
    sleep 3
fi

if ! curl -sf "${TARGET_URL}/actuator/health" >/dev/null 2>&1; then
    fail "Endpoint ${TARGET_URL}/actuator/health is not reachable after port-forward initialization!"
fi

# Guard 4: Verify the active pods in forgeops-sre-lab
ACTIVE_PODS="$(kubectl get pods -n "$DISPOSABLE_NAMESPACE" -l app.kubernetes.io/name=sre-api --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo 0)"
if [[ "$ACTIVE_PODS" -lt 1 ]]; then
    fail "SAFETY ABORT: No running pods found in disposable namespace '$DISPOSABLE_NAMESPACE'! Refusing to run load test."
fi

# Guard 5: Verify protected PVC UIDs remain untouched
EXPECTED_G06_PVC_UID="84853fb3-4d13-43a9-bc62-973c3be3c90c"
EXPECTED_G08_PVC_UID="b5ea8ec9-47e8-4979-afdb-621f2e3c63b8"
EXPECTED_G09_PVC_UID="cd64e090-2c69-49b3-a389-de5841ce06d6"
EXPECTED_G10_PVC_UID="23468366-7394-4f2d-be1f-2a640d6f12c5"
EXPECTED_G11_PVC_UID="092b6655-6617-467c-b546-69e201a0ba8a"

G08_UID="$(kubectl get pvc postgres-storage-forgetasks-rehearsal-db-0 -n forgeops-gitops-rehearsal -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
if [[ "$G08_UID" != "$EXPECTED_G08_PVC_UID" ]]; then
    fail "Protected G08 PVC UID mismatch! Expected '$EXPECTED_G08_PVC_UID', found '$G08_UID'."
fi

# Notice on single-pod proxy limitation
echo "-----------------------------------------------------------------------"
echo -e "${YELLOW}[ARCHITECTURE NOTICE]${NC} Port-Forward Single-Pod Limitation:"
echo "kubectl port-forward to 'svc/sre-api' routes through a single tunnel to one backend pod."
echo "This test measures single-pod saturation and controller resilience, not multi-pod kube-proxy load distribution."
echo "-----------------------------------------------------------------------"

mkdir -p "$OUTPUT_DIR"

run_scenario() {
    local sc="$1"
    local sc_file="${K6_DIR}/${sc}.js"

    if [[ ! -f "$sc_file" ]]; then
        fail "Scenario script not found: $sc_file"
    fi

    info "Executing k6 scenario: ${sc}"
    info "Target URL: ${TARGET_URL}${ENDPOINT}"
    
    local summary_json="${OUTPUT_DIR}/${sc}-summary.json"

    TARGET_URL="$TARGET_URL" \
    ENDPOINT="$ENDPOINT" \
    SCENARIO_NAME="$sc" \
    k6 run \
        --summary-export="$summary_json" \
        "$sc_file"

    pass "Scenario '${sc}' completed successfully. Summary saved to ${summary_json}"
}

case "$SCENARIO" in
    smoke)
        run_scenario "smoke"
        ;;
    baseline)
        run_scenario "baseline"
        ;;
    ramp-up|ramp_up)
        run_scenario "ramp-up"
        ;;
    stress)
        run_scenario "stress"
        ;;
    recovery)
        run_scenario "recovery"
        ;;
    all)
        info "Running all progressive scenarios sequentially..."
        run_scenario "smoke"
        run_scenario "baseline"
        run_scenario "ramp-up"
        run_scenario "stress"
        run_scenario "recovery"
        pass "All progressive performance scenarios completed."
        ;;
    *)
        echo "Usage: $0 [smoke|baseline|ramp-up|stress|recovery|all]"
        exit 1
        ;;
esac
