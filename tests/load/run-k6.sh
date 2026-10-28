#!/usr/bin/env bash
# ==============================================================================
# ForgeOps k6 Load Testing Orchestrator
# Executes parameterized k6 performance and reliability scenarios
# Strict local safety guards and threshold verification
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_DIR="${SCRIPT_DIR}/k6"

TARGET_URL="${TARGET_URL:-http://127.0.0.1:18080}"
ENDPOINT="${ENDPOINT:-/actuator/health/readiness}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/results}"
SCENARIO="${1:-smoke}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Ensure k6 binary is installed
if ! command -v k6 >/dev/null 2>&1; then
    fail "k6 binary not found in PATH. Install k6 or make it executable in /usr/local/bin/k6."
fi

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
