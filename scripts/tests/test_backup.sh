#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/backup.sh (Phase 4).
# Usage: ./scripts/tests/test_backup.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

BACKUP="$REPO_ROOT/scripts/backup.sh"
TEST_OUT="$REPO_ROOT/data/backups-test"

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# shellcheck disable=SC2329   # invoked via trap EXIT
cleanup() {
    rm -rf "$TEST_OUT" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Syntax
bash -n "$BACKUP" && pass "bash -n syntax check" || fail "bash -n syntax check"

# 2. --help exits 0
set +e; "$BACKUP" --help >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 0 ] && pass "--help exits 0 (got $code)" || fail "--help exits 0 (got $code)"

# 3. Unknown flag exits 2
set +e; "$BACKUP" --bogus >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "unknown flag exits 2 (got $code)" || fail "unknown flag exits 2 (got $code)"

# 4. Missing --out value exits 2
set +e; "$BACKUP" --out >/dev/null 2>&1; code=$?; set -e
[ "$code" -eq 2 ] && pass "missing --out value exits 2 (got $code)" || fail "missing --out value exits 2 (got $code)"

# 5. Creates a verified archive and exits 0
set +e
"$BACKUP" --out "$TEST_OUT" >/tmp/backup-run.log 2>&1
code=$?
set -e
archive="$(find "$TEST_OUT" -maxdepth 1 -name 'imageflow-*.tar.gz' -type f -print 2>/dev/null | sort | tail -1 || true)"
if [ "$code" -eq 0 ] && [ -n "$archive" ] && tar -tzf "$archive" >/dev/null 2>&1; then
    pass "archive created and verified, exits 0 (got $code)"
else
    fail "archive created and verified, exits 0 (got $code)"
    tail -5 /tmp/backup-run.log 2>/dev/null || true
fi

echo
if [ "$failed_tests" -eq 0 ]; then
    echo "ALL TESTS PASSED ($passed passed)"
    exit 0
else
    echo "$failed_tests TEST(S) FAILED ($passed passed)"
    exit 1
fi
