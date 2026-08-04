#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/deploy.sh (Phase 4).
# Usage: ./scripts/tests/test_deploy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

DEPLOY="$REPO_ROOT/scripts/deploy.sh"
VENV_UVICORN="$REPO_ROOT/.venv/bin/uvicorn"
MOCK_FLOCI_PORT=4567
API_PORT=8031
API_PID=""
MOCK_PID=""

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# shellcheck disable=SC2317,SC2329   # invoked via trap EXIT (code differs by shellcheck version)
cleanup() {
    [ -n "$API_PID" ]  && kill "$API_PID"  2>/dev/null || true
    [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
    [ -f "$REPO_ROOT/data/api.pid" ] && kill "$(cat "$REPO_ROOT/data/api.pid")" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Syntax
bash -n "$DEPLOY" && pass "bash -n syntax check" || fail "bash -n syntax check"

# 2. --help exits 0
set +e; "$DEPLOY" --help >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 0 ] && pass "--help exits 0 (got $code)" || fail "--help exits 0 (got $code)"

# 3. Unknown flag exits 2
set +e; "$DEPLOY" --bogus >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "unknown flag exits 2 (got $code)" || fail "unknown flag exits 2 (got $code)"

# 4. Missing option value exits 2
set +e; "$DEPLOY" --api-port >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "missing option value exits 2 (got $code)" || fail "missing option value exits 2 (got $code)"

# 5. Non-numeric port exits 2
set +e; "$DEPLOY" --api-port abc >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "non-numeric port exits 2 (got $code)" || fail "non-numeric port exits 2 (got $code)"

# 6. Missing terraform/opentofu (hidden via PATH) exits 1
set +e
PATH="/usr/bin:/bin" "$DEPLOY" --skip-api --skip-smoke >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 1 ] && pass "missing terraform exits 1 (got $code)" || fail "missing terraform exits 1 (got $code)"

# 7. Unreachable Floci (prereq check) exits 1
set +e
"$DEPLOY" --skip-terraform --skip-api --floci-url http://127.0.0.1:9 >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 1 ] && pass "unreachable Floci exits 1 (got $code)" || fail "unreachable Floci exits 1 (got $code)"

# 8. Smoke path (skip tf + api, real servers running) exits 0
if [ ! -x "$VENV_UVICORN" ]; then
    fail "smoke-path test skipped (venv uvicorn not found)"
else
    "$VENV_UVICORN" app.main:app --host 127.0.0.1 --port "$API_PORT" >/tmp/deploy-api.log 2>&1 &
    API_PID=$!
    python3 -m http.server "$MOCK_FLOCI_PORT" --bind 127.0.0.1 >/tmp/deploy-floci.log 2>&1 &
    MOCK_PID=$!
    sleep 2

    if ! kill -0 "$API_PID" 2>/dev/null || ! kill -0 "$MOCK_PID" 2>/dev/null; then
        fail "smoke-path servers did not start (API_PID=$API_PID, MOCK_PID=$MOCK_PID)"
        tail -5 /tmp/deploy-api.log 2>/dev/null || true
    else
        set +e
        "$DEPLOY" --skip-terraform --skip-api --api-port "$API_PORT" \
            --floci-url "http://127.0.0.1:$MOCK_FLOCI_PORT" >/tmp/deploy-run.log 2>&1
        code=$?
        set -e
        if [ "$code" -eq 0 ]; then
            pass "smoke path exits 0 (got $code)"
        else
            fail "smoke path exits 0 (got $code)"
            tail -5 /tmp/deploy-run.log 2>/dev/null || true
        fi
    fi

    # 9. Full deploy path (deploy starts the API itself) exits 0
    set +e
    "$DEPLOY" --skip-terraform --api-port 8032 \
        --floci-url "http://127.0.0.1:$MOCK_FLOCI_PORT" >/tmp/deploy-full.log 2>&1
    code=$?
    set -e
    if [ "$code" -eq 0 ]; then
        pass "full deploy (API start + smoke) exits 0 (got $code)"
        if [ -f "$REPO_ROOT/data/api.pid" ]; then API_PID="$(cat "$REPO_ROOT/data/api.pid")"; fi
    else
        fail "full deploy (API start + smoke) exits 0 (got $code)"
        tail -5 /tmp/deploy-full.log 2>/dev/null || true
        tail -5 "$REPO_ROOT/data/api.log" 2>/dev/null || true
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
