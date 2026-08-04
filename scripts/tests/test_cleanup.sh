#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/cleanup.sh (Phase 4).
# Usage: ./scripts/tests/test_cleanup.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CLEANUP="$REPO_ROOT/scripts/cleanup.sh"

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# 1. Syntax
bash -n "$CLEANUP" && pass "bash -n syntax check" || fail "bash -n syntax check"

# 2. --help exits 0
set +e; "$CLEANUP" --help >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 0 ] && pass "--help exits 0 (got $code)" || fail "--help exits 0 (got $code)"

# 3. Unknown flag exits 2
set +e; "$CLEANUP" --bogus >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "unknown flag exits 2 (got $code)" || fail "unknown flag exits 2 (got $code)"

# 4. Abort on non-yes answer (echo n) exits 0, leaves data intact
mkdir -p "$REPO_ROOT/data"
printf 'x' > "$REPO_ROOT/data/api.log"
set +e
printf 'n\n' | "$CLEANUP" --tf-dir "$REPO_ROOT/does-not-exist" >/dev/null 2>&1
code=$?
set -e
if [ "$code" -eq 0 ] && [ -f "$REPO_ROOT/data/api.log" ]; then
    pass "abort on 'n' exits 0 and keeps artifacts (got $code)"
else
    fail "abort on 'n' exits 0 and keeps artifacts (got $code)"
fi

# 5. --yes removes runtime artifacts and exits 0 (no terraform binary present → skip)
set +e
PATH="/usr/bin:/bin" "$CLEANUP" --yes --tf-dir "$REPO_ROOT/does-not-exist" >/dev/null 2>&1
code=$?
set -e
if [ "$code" -eq 0 ] && [ ! -f "$REPO_ROOT/data/api.log" ]; then
    pass "--yes removes artifacts and exits 0 (got $code)"
else
    fail "--yes removes artifacts and exits 0 (got $code)"
fi
rmdir "$REPO_ROOT/data" 2>/dev/null || true

echo
if [ "$failed_tests" -eq 0 ]; then
    echo "ALL TESTS PASSED ($passed passed)"
    exit 0
else
    echo "$failed_tests TEST(S) FAILED ($passed passed)"
    exit 1
fi
