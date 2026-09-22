#!/usr/bin/env bash
#
# run_tests.sh - Backstage Label Analytics
# Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22
#
# Runs the correctness and access suites and exits non-zero on any failure.
#
#   bash tools/run_tests.sh --connection <snow-connection-name>
#
# The access suite runs once per persona role with secondary roles disabled.
# Running it as SYSADMIN would pass trivially, because SYSADMIN holds entitlements
# on every label, so the role is pinned explicitly on every invocation.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECTION=""
WAREHOUSE="SFE_BACKSTAGE_ANALYTICS_WH"
PERSONAS=(BACKSTAGE_LABEL_BROAD BACKSTAGE_LABEL_LIMITED BACKSTAGE_LABEL_NONE)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --connection) CONNECTION="${2:-}"; shift 2 ;;
        --warehouse)  WAREHOUSE="${2:-}";  shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$CONNECTION" ]]; then
    echo "ERROR: --connection is required." >&2
    echo "Usage: bash tools/run_tests.sh --connection <snow-connection-name>" >&2
    exit 2
fi

FAILURES=0
LOG_DIR="$(mktemp -d)"

banner() { printf '\n=== %s ===\n' "$1"; }

# --------------------------------------------------------------------------
# Suite 1: reference queries. Correctness ground truth, run with broad scope.
# Compare the output against docs/EXPECTED_RESULTS.md.
# --------------------------------------------------------------------------
banner "Reference queries (BACKSTAGE_LABEL_BROAD)"
REF_LOG="$LOG_DIR/reference.log"
if snow sql --connection "$CONNECTION" \
            --role BACKSTAGE_LABEL_BROAD \
            --secondary-roles NONE \
            --warehouse "$WAREHOUSE" \
            --format csv \
            --filename "$ROOT/tests/01_reference_queries.sql" > "$REF_LOG" 2>&1; then
    echo "Reference queries executed."
else
    echo "FAIL: reference queries did not execute cleanly."
    tail -30 "$REF_LOG"
    FAILURES=$((FAILURES + 1))
fi

# Spot-check the three headline values against docs/EXPECTED_RESULTS.md. These are
# the numbers a presenter will read aloud, so a silent drift here is the most
# expensive failure in the project.
check_value() {
    local label="$1" pattern="$2"
    if grep -qF -- "$pattern" "$REF_LOG"; then
        echo "  PASS  $label"
    else
        echo "  FAIL  $label (expected to find: $pattern)"
        FAILURES=$((FAILURES + 1))
    fi
}

banner "Expected value spot checks"
check_value "Q1 concentration 9.31% of \$28,609,484.50" "2664931.35,28609484.50,9.31"
check_value "Q1 verdict ANSWERABLE for broad scope"     "ANSWERABLE"
check_value "Q2 population: 75 labels, 69 increased"    "75,69,6,0"
check_value "Q2 top mover Foxglove Audio +11827.46"     "Foxglove Audio,268867.40,280694.86,11827.46,4.4%"
check_value "Q3 YouTube coverage 24 of 31 days"         "YouTube,24,7"
check_value "Q4 window 2026-09-09 to 2026-09-15"        "2026-09-09,2026-09-15,7"
check_value "Q5 peak tie on 2025-06-14 at 98750"        "2025-06-14,98750"
check_value "Q5 peak tie on 2026-02-21 at 98750"        "2026-02-21,98750"

# --------------------------------------------------------------------------
# Suite 2: access tests, once per persona.
#
# Test 6 deliberately expects a privilege error, so a non-zero exit from snow sql
# is not by itself a failure here. Verdicts are read from the output instead.
# --------------------------------------------------------------------------
for ROLE in "${PERSONAS[@]}"; do
    banner "Access tests ($ROLE)"
    ACCESS_LOG="$LOG_DIR/access-$ROLE.log"
    snow sql --connection "$CONNECTION" \
             --role "$ROLE" \
             --secondary-roles NONE \
             --warehouse "$WAREHOUSE" \
             --format csv \
             --filename "$ROOT/tests/02_access_tests.sql" > "$ACCESS_LOG" 2>&1

    if grep -q "^FAIL\|,FAIL" "$ACCESS_LOG" || grep -qE "FAIL: " "$ACCESS_LOG"; then
        echo "FAIL: one or more access assertions failed for $ROLE"
        grep -E "FAIL" "$ACCESS_LOG" | head -10
        FAILURES=$((FAILURES + 1))
    else
        PASSES=$(grep -c "PASS" "$ACCESS_LOG" || true)
        SKIPS=$(grep -c "SKIP" "$ACCESS_LOG" || true)
        echo "  $PASSES assertions passed, $SKIPS skipped (skips are expected; each test targets specific personas)"
    fi

    # Test 6 must have produced a privilege error. If ENTITLEMENT was readable,
    # a persona could inspect or alter its own authorization.
    if grep -qiE "insufficient privileges|does not exist or not authorized" "$ACCESS_LOG"; then
        echo "  PASS  ENTITLEMENT is not readable by $ROLE"
    else
        echo "  FAIL  ENTITLEMENT appears readable by $ROLE"
        FAILURES=$((FAILURES + 1))
    fi
done

banner "Summary"
if [[ "$FAILURES" -eq 0 ]]; then
    echo "All checks passed."
    echo "Logs: $LOG_DIR"
    exit 0
fi

echo "$FAILURES check group(s) failed."
echo "Logs: $LOG_DIR"
exit 1
