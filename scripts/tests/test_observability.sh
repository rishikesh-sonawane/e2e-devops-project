#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/observability.sh (Phase 13).
# Usage: ./scripts/tests/test_observability.sh
#
# Strategy: a fake `aws` CLI is put on PATH with canned JSON responses, so the
# script's reporting logic is tested deterministically without Floci. Covers:
# syntax, --help (0), unknown flag (2), missing value (2), bad --hours (2),
# happy path with data (0 + expected output), and aws-down (1).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SCRIPT="$REPO_ROOT/scripts/observability.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# ── Fake aws CLI ─────────────────────────────────────────────────────
# Usage: fake-aws <service> <command> ...   → canned JSON matching the
# --query/--output text projections the script requests.
cat > "$FAKE_BIN/aws" <<'FAKE'
#!/usr/bin/env bash
# shellcheck shell=bash
service="${1:-}"; cmd="${2:-}"
case "${IMAGEFLOW_FAKE_AWS_MODE:-happy}" in
    down)
        case "$service" in
            cloudwatch) echo "cloudwatch down" >&2; exit 1 ;;
        esac
        ;;
esac
case "$service/$cmd" in
    cloudwatch/get-metric-statistics) printf '42.0\n' ;;
    cloudwatch/describe-alarms)       printf 'imageflow-failed-images\tOK\nimageflow-upload-errors\tOK\n' ;;
    events/list-rules)                printf 'imageflow-alarm-events\tENABLED\n' ;;
    events/list-targets-by-rule)      printf 'arn:aws:sns:us-east-1:000000000000:imageflow-events\n' ;;
    logs/filter-log-events)           printf 'api: healthy\n' ;;
    sns/list-topics)                  printf 'arn:aws:sns:us-east-1:000000000000:imageflow-events\n' ;;
    *) echo "unexpected: $service $cmd" >&2; exit 2 ;;
esac
FAKE
chmod +x "$FAKE_BIN/aws"

export PATH="$FAKE_BIN:$PATH"

# 1. Syntax
if bash -n "$SCRIPT"; then pass "bash -n syntax check"; else fail "bash -n syntax check"; fi

# 2. --help exits 0
set +e
"$SCRIPT" --help >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 0 ] && pass "--help exits 0 (got $code)" || fail "--help exits 0 (got $code)"

# 3. Unknown flag exits 2
set +e
"$SCRIPT" --bogus >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "unknown flag exits 2 (got $code)" || fail "unknown flag exits 2 (got $code)"

# 4. Missing option value exits 2
set +e
"$SCRIPT" --namespace >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "missing option value exits 2 (got $code)" || fail "missing option value exits 2 (got $code)"

# 5. Non-numeric --hours exits 2
set +e
"$SCRIPT" --hours abc >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 2 ] && pass "non-numeric --hours exits 2 (got $code)" || fail "non-numeric --hours exits 2 (got $code)"

# 6. Happy path: fake aws responds → exit 0 + expected sections
set +e
out="$("$SCRIPT" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ] && \
   printf '%s' "$out" | grep -q "namespace=ImageFlow" && \
   printf '%s' "$out" | grep -q "imageflow-failed-images" && \
   printf '%s' "$out" | grep -q "imageflow-alarm-events"; then
    pass "happy path exits 0 and reports metrics+alarms+rules"
else
    fail "happy path exits 0 and reports metrics+alarms+rules (got $code: $out)"
fi

# 7. aws down (CloudWatch unreachable) → core section fails → exit 1
set +e
IMAGEFLOW_FAKE_AWS_MODE=down "$SCRIPT" >/dev/null 2>&1
code=$?
set -e
[ "$code" -eq 1 ] && pass "CloudWatch unavailable exits 1 (got $code)" || fail "CloudWatch unavailable exits 1 (got $code)"

echo
echo "observability tests: $passed passed, $failed_tests failed"
[ "$failed_tests" -eq 0 ]
