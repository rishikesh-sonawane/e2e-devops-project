#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/security.sh + scripts/security-audit.sh (Phase 14).
# Usage: ./scripts/tests/test_security.sh
#
# Strategy: a fake `aws` CLI on PATH serves canned responses; the audit's
# secret scan is exercised against throwaway temp dirs (never real secrets in
# the repo). Covers syntax, exit codes, happy paths, and failure paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SECURITY="$REPO_ROOT/scripts/security.sh"
AUDIT="$REPO_ROOT/scripts/security-audit.sh"
FAKE_BIN="$(mktemp -d)"
SCAN_DIR="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN" "$SCAN_DIR"' EXIT

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# ── Fake aws CLI ─────────────────────────────────────────────────────
cat > "$FAKE_BIN/aws" <<'FAKE'
#!/usr/bin/env bash
# shellcheck shell=bash
service="${1:-}"; cmd="${2:-}"
mode="${IMAGEFLOW_FAKE_AWS_MODE:-happy}"
case "$service/$cmd" in
    kms/encrypt)
        [ "$mode" = down ] && { echo down >&2; exit 1; }
        printf 'Y2lwaGVydGV4dA==\n' ;;
    kms/decrypt)
        # base64 of "imageflow-demo-plaintext" — the script decodes it.
        printf 'aW1hZ2VmbG93LWRlbW8tcGxhaW50ZXh0\n' ;;
    secretsmanager/put-secret-value) printf '{}\n' ;;
    secretsmanager/get-secret-value) printf '{"token":"x","environment":"dev"}\n' ;;
    cognito-idp/list-user-pools)     printf 'us-east-1_abc123\n' ;;
    cognito-idp/list-user-pool-clients) printf 'client123\n' ;;
    cognito-idp/admin-create-user)   printf '{}\n' ;;
    cognito-idp/admin-initiate-auth) printf 'session123\n' ;;
    cognito-idp/admin-respond-to-auth-challenge)
        printf 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzZWMtZGVtbyIsImlzcyI6ImNvZ25pdG8taWRwIiwidXNlcm5hbWUiOiJzZWMtZGVtbzEyMyJ9.c2ln\n' ;;
    cognito-idp/admin-delete-user)   printf '{}\n' ;;
    wafv2/list-web-acls)             printf 'acl123\n' ;;
    wafv2/get-web-acl)
        printf '[["rate-limit",{"Block":{}},{"RateBasedStatement":{"Limit":100}}],["aws-managed-common",{"None":{}},{"ManagedRuleGroupStatement":{"Name":"AWSManagedRulesCommonRuleSet"}}]]\n' ;;
    iam/get-user)
        [ "$mode" = down ] && { echo down >&2; exit 1; }
        printf 'imageflow-reader\n' ;;
    iam/get-user-policy)
        case "$mode" in
            wildcard)
                printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["*"],"Resource":["*"]}]}\n' ;;
            down) echo down >&2; exit 1 ;;
            *) printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::imageflow-uploads/*"]}]}\n' ;;
        esac ;;
    iam/list-users)                  printf 'imageflow-reader\n' ;;
    iam/list-user-policies)          printf 'read-uploads-only\n' ;;
    *) echo "unexpected: $service $cmd" >&2; exit 2 ;;
esac
FAKE
chmod +x "$FAKE_BIN/aws"
export PATH="$FAKE_BIN:$PATH"

# ── 1. Syntax ────────────────────────────────────────────────────────
if bash -n "$SECURITY" && bash -n "$AUDIT"; then pass "bash -n syntax check (both scripts)"; else fail "bash -n syntax check (both scripts)"; fi

# ── 2. --help exits 0 ────────────────────────────────────────────────
set +e
"$SECURITY" --help >/dev/null 2>&1; c1=$?
"$AUDIT" --help >/dev/null 2>&1; c2=$?
set -e
[ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && pass "--help exits 0 (got $c1/$c2)" || fail "--help exits 0 (got $c1/$c2)"

# ── 3. Unknown demo / flag / missing value exit 2 ────────────────────
set +e
"$SECURITY" bogus >/dev/null 2>&1; c1=$?
"$AUDIT" --bogus >/dev/null 2>&1; c2=$?
"$AUDIT" --repo-dir >/dev/null 2>&1; c3=$?
set -e
[ "$c1" -eq 2 ] && [ "$c2" -eq 2 ] && [ "$c3" -eq 2 ] \
    && pass "unknown demo/flag/missing value exit 2 (got $c1/$c2/$c3)" \
    || fail "unknown demo/flag/missing value exit 2 (got $c1/$c2/$c3)"

# ── 4. security.sh happy path: all demos exit 0 ──────────────────────
set +e
out="$("$SECURITY" all 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "round trip OK" \
    && printf '%s' "$out" | grep -q "stored keys: environment, token" \
    && printf '%s' "$out" | grep -q '"sub": "sec-demo"' \
    && printf '%s' "$out" | grep -q "rate-limit" \
    && printf '%s' "$out" | grep -q "scoped policy (single bucket, read-only)"; then
    pass "security.sh all demos exit 0 with expected output"
else
    fail "security.sh all demos exit 0 with expected output (got $c: $(printf '%s' "$out" | head -5))"
fi

# ── 5. security.sh aws down → exit 1 ─────────────────────────────────
set +e
IMAGEFLOW_FAKE_AWS_MODE=down "$SECURITY" kms >/dev/null 2>&1
c=$?
set -e
[ "$c" -eq 1 ] && pass "security.sh kms with aws down exits 1 (got $c)" || fail "security.sh kms with aws down exits 1 (got $c)"

# ── 6. audit: clean dir exits 0 ──────────────────────────────────────
echo "def hello(): return 42" > "$SCAN_DIR/clean.py"
set +e
"$AUDIT" --repo-dir "$SCAN_DIR" >/dev/null 2>&1
c=$?
set -e
[ "$c" -eq 0 ] && pass "audit clean dir exits 0 (got $c)" || fail "audit clean dir exits 0 (got $c)"

# ── 7. audit: secret found → exit 1 + finding reported ───────────────
# Build the fake key from parts so this test file never contains the literal
# high-signal pattern (the audit + gitleaks would flag the test itself).
fake_key="AKI$(printf 'A1234567890ABCDEF')"
echo "aws_key = \"$fake_key\"" > "$SCAN_DIR/leak.py"
set +e
out="$("$AUDIT" --repo-dir "$SCAN_DIR" 2>&1)"
c=$?
set -e
if [ "$c" -eq 1 ] && printf '%s' "$out" | grep -q "SECRET-SCAN FINDINGS"; then
    pass "audit flags hardcoded secret → exit 1"
else
    fail "audit flags hardcoded secret → exit 1 (got $c)"
fi
rm -f "$SCAN_DIR/leak.py"

# ── 8. audit: IAM wildcard flagged (info) ────────────────────────────
set +e
out="$(IMAGEFLOW_FAKE_AWS_MODE=wildcard "$AUDIT" --repo-dir "$SCAN_DIR" 2>&1)"
c=$?
set -e
printf '%s' "$out" | grep -q "wildcard Resource/Action" \
    && pass "audit flags IAM wildcard statements" \
    || fail "audit flags IAM wildcard statements (got: $(printf '%s' "$out" | tail -2))"

echo
echo "security tests: $passed passed, $failed_tests failed"
[ "$failed_tests" -eq 0 ]
