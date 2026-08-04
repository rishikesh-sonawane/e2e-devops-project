#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/health-check.sh (Phase 4).
# Usage: ./scripts/tests/test_health-check.sh
#
# Covers: syntax, --help (exit 0), unknown flag (exit 2), missing option
# value (exit 2), all-down (exit 1), and all-up (exit 0) against real local
# HTTP servers (FastAPI via the repo venv + a throwaway http.server for Floci).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

HEALTH_CHECK="$REPO_ROOT/scripts/health-check.sh"
VENV_UVICORN="$REPO_ROOT/.venv/bin/uvicorn"

API_PORT=8022
MOCK_FLOCI_PORT=4567
API_PID=""
MOCK_PID=""

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# shellcheck disable=SC2329   # invoked via trap EXIT
cleanup() {
    [ -n "$API_PID" ]  && kill "$API_PID"  2>/dev/null || true
    [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Syntax
if bash -n "$HEALTH_CHECK"; then pass "bash -n syntax check"; else fail "bash -n syntax check"; fi

# 2. --help exits 0
set +e
"$HEALTH_CHECK" --help >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 0 ] && pass "--help exits 0 (got $code)" || fail "--help exits 0 (got $code)"

# 3. Unknown flag exits 2
set +e
"$HEALTH_CHECK" --bogus >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "unknown flag exits 2 (got $code)" || fail "unknown flag exits 2 (got $code)"

# 4. Missing option value exits 2
set +e
"$HEALTH_CHECK" --timeout >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "missing option value exits 2 (got $code)" || fail "missing option value exits 2 (got $code)"

# 5. Everything down exits 1 (port 9 = discard, reliably refuses/ignores)
set +e
"$HEALTH_CHECK" --api-url "http://127.0.0.1:9" --floci-url "http://127.0.0.1:9" --timeout 1 >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 1 ] && pass "all services down exits 1 (got $code)" || fail "all services down exits 1 (got $code)"

# 5b. Non-numeric timeout exits 2
set +e
"$HEALTH_CHECK" --timeout abc >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "non-numeric timeout exits 2 (got $code)" || fail "non-numeric timeout exits 2 (got $code)"

# 6. Everything up exits 0 (real servers)
if [ ! -x "$VENV_UVICORN" ]; then
    fail "all-up test skipped (venv uvicorn not found at $VENV_UVICORN)"
else
    "$VENV_UVICORN" app.main:app --host 127.0.0.1 --port "$API_PORT" >/tmp/hc-api.log 2>&1 &
    API_PID=$!
    python3 -m http.server "$MOCK_FLOCI_PORT" --bind 127.0.0.1 >/tmp/hc-floci.log 2>&1 &
    MOCK_PID=$!
    sleep 2

    # Readiness guard: if a stale server holds the port, the new one dies
    # and kill -0 fails — no false pass against an unexpected process.
    if ! kill -0 "$API_PID" 2>/dev/null || ! kill -0 "$MOCK_PID" 2>/dev/null; then
        fail "servers did not start (API_PID=$API_PID, MOCK_PID=$MOCK_PID)"
        tail -5 /tmp/hc-api.log 2>/dev/null || true
        tail -5 /tmp/hc-floci.log 2>/dev/null || true
    else
        set +e
        "$HEALTH_CHECK" \
            --api-url "http://127.0.0.1:$API_PORT" \
            --floci-url "http://127.0.0.1:$MOCK_FLOCI_PORT" \
            --timeout 2 >/tmp/hc-run.log 2>&1
        code=$?
        set -e

        if [ "$code" -eq 0 ]; then
            pass "all services up exits 0 (got $code)"
        else
            fail "all services up exits 0 (got $code)"
            tail -5 /tmp/hc-run.log 2>/dev/null || true
            tail -5 /tmp/hc-api.log 2>/dev/null || true
        fi
    fi
fi

echo
if [ "$failed_tests" -eq 0 ]; then
    echo "ALL TESTS PASSED ($passed passed)"
    exit 0
else
    echo "$failed_tests TEST(S) FAILED ($passed passed)"
    exit 1
fi
