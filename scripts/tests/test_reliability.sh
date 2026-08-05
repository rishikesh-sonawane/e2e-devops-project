#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2015   # A && B || C pattern used deliberately in assertions
#
# Behavior tests for scripts/reliability.sh (Phase 15).
# Usage: ./scripts/tests/test_reliability.sh
#
# Strategy: a stateful Python fake `aws` (real item store in a temp file, so
# put/scan/delete/batch-write round trips behave like DynamoDB) + a fake
# `kubectl` on PATH. Covers syntax, exit codes, happy paths, and failure
# paths for every subcommand.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

RELIABILITY="$REPO_ROOT/scripts/reliability.sh"
FAKE_BIN="$(mktemp -d)"
TEST_BACKUP_DIR="$(mktemp -d)/backups"
FAKE_STATE="$(mktemp)"
API_PID=""
export IMAGEFLOW_BACKUP_DIR="$TEST_BACKUP_DIR"
export IMAGEFLOW_FAKE_STATE="$FAKE_STATE"
# shellcheck disable=SC2317,SC2329   # invoked via trap EXIT (code differs by shellcheck version)
cleanup() {
    [ -n "$API_PID" ] && kill "$API_PID" 2>/dev/null || true
    [ -f "$REPO_ROOT/data/api.pid" ] && kill "$(cat "$REPO_ROOT/data/api.pid")" 2>/dev/null || true
    rm -rf "$FAKE_BIN" "$TEST_BACKUP_DIR" "$FAKE_STATE"
}
trap cleanup EXIT

passed=0
failed_tests=0

pass() { printf '[PASS] %s\n' "$*"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; failed_tests=$((failed_tests + 1)); }

# ── Fake aws CLI (stateful Python — emulates DynamoDB well enough to round
# trip put/scan/batch-write/delete, supports minimal --query extraction, and
# simulates the Lambda lifecycle for fail-image: PENDING → FAILED (3rd poll)
# → PROCESSED (after reset). ──────────────────────────────────────────────
cat > "$FAKE_BIN/aws" <<'FAKE'
#!/usr/bin/env python3
import json, os, sys

SERVICE, CMD = sys.argv[1], sys.argv[2]
MODE = os.environ.get("IMAGEFLOW_FAKE_AWS_MODE", "happy")
STATE = os.environ["IMAGEFLOW_FAKE_STATE"]

def load():
    items = {}
    if os.path.exists(STATE):
        for line in open(STATE):
            item = json.loads(line)
            items[item["image_id"]["S"]] = item
    return items

def save(items):
    with open(STATE, "w") as f:
        for item in items.values():
            f.write(json.dumps(item) + "\n")

def arg(name):
    for i, a in enumerate(sys.argv):
        if a == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None

def key_from(argval):
    return json.loads(argval)["image_id"]["S"]

# Minimal JMESPath for the queries the script uses: "Item", "Item.status.S",
# "Item.image_id.S", "AutoScalingGroups[0].DesiredCapacity",
# "length(AutoScalingGroups[0].Instances)".
def query_path(data, q):
    if not q:
        return data
    is_length = q.startswith("length(")
    q = q.replace("length(", "").replace(")", "")
    cur = data
    for part in q.split("."):
        part = part.strip()
        # Index brackets may be glued to the key: AutoScalingGroups[0] →
        # key AutoScalingGroups, then descend into index 0.
        if "[" in part:
            key, rest = part.split("[", 1)
            if key and isinstance(cur, dict):
                cur = cur.get(key)
            idx = int(rest.rstrip("]"))
            cur = cur[idx] if isinstance(cur, list) and idx < len(cur) else None
            continue
        cur = cur.get(part) if isinstance(cur, dict) else None
        if cur is None:
            return None
    if is_length and isinstance(cur, (list, dict)):
        return len(cur)
    return cur

def emit(data, q):
    val = query_path(data, q)
    if val is None:
        print("")
    elif isinstance(val, (dict, list)):
        print(json.dumps(val))
    else:
        print(str(val))

if SERVICE == "dynamodb" and CMD == "scan":
    if MODE == "down":
        sys.exit(1)
    emit({"Items": list(load().values())}, arg("--query"))

elif SERVICE == "dynamodb" and CMD == "batch-write-item":
    if MODE == "down":
        sys.exit(1)
    reqs = json.loads(arg("--request-items"))
    items = load()
    for table_reqs in reqs.values():
        for r in table_reqs:
            if "PutRequest" in r:
                it = r["PutRequest"]["Item"]
                items[it["image_id"]["S"]] = it
    save(items)
    print(json.dumps({"UnprocessedItems": {}}))

elif SERVICE == "dynamodb" and CMD == "put-item":
    items = load()
    it = json.loads(arg("--item"))
    items[it["image_id"]["S"]] = it
    save(items)
    print("{}")

elif SERVICE == "dynamodb" and CMD == "delete-item":
    items = load()
    items.pop(key_from(arg("--key")), None)
    save(items)
    print("{}")

elif SERVICE == "dynamodb" and CMD == "update-item":
    items = load()
    k = key_from(arg("--key"))
    if MODE == "failed":
        # The script's fix step marks the object "fixed" — from here the fake
        # Lambda reports PROCESSED (retry recovery) instead of FAILED.
        with open(STATE + ".fixed", "w") as f:
            f.write("1")
        items[k]["status"]["S"] = "PROCESSED"
    else:
        items[k]["status"]["S"] = "PENDING"
    save(items)
    print("{}")

elif SERVICE == "dynamodb" and CMD == "get-item":
    k = key_from(arg("--key"))
    items = load()
    item = items.get(k)
    if MODE == "failed" and k.startswith("fail-image") and item is not None:
        if not os.path.exists(STATE + ".fixed"):
            n = 0
            pf = STATE + ".poll"
            if os.path.exists(pf):
                n = int(open(pf).read())
            n += 1
            open(pf, "w").write(str(n))
            item["status"]["S"] = "PENDING" if n < 3 else "FAILED"
            if item["status"]["S"] == "FAILED":
                item["error"] = {"S": "invalid image data: UnidentifiedImageError"}
    emit({"Item": item} if item is not None else {}, arg("--query"))

elif SERVICE == "s3" and CMD == "sync":
    print("Completed 1 files...")
elif SERVICE == "s3" and CMD == "cp":
    print("upload: x to y")
elif SERVICE == "s3" and CMD == "rm":
    print("delete: y")
elif SERVICE == "s3api" and CMD == "head-object":
    print("68")

elif SERVICE == "lambda" and CMD == "invoke":
    print("{}")

elif SERVICE == "autoscaling" and CMD == "describe-auto-scaling-groups":
    if MODE == "noasg":
        print("")
    elif MODE == "drift":
        emit({"AutoScalingGroups": [{"AutoScalingGroupName": "imageflow-asg", "DesiredCapacity": 1, "Instances": []}]}, arg("--query"))
    elif MODE == "killinst":
        # kill-instance lifecycle: first describe returns the OLD instance,
        # later describes return the NEW one (reconciled replacement).
        n = 0
        kf = STATE + ".ki"
        if os.path.exists(kf):
            n = int(open(kf).read())
        n += 1
        open(kf, "w").write(str(n))
        inst = {"InstanceId": "i-old-1", "LifecycleState": "InService"} if n == 1 else {"InstanceId": "i-new-2", "LifecycleState": "Pending"}
        emit({"AutoScalingGroups": [{"AutoScalingGroupName": "imageflow-asg", "DesiredCapacity": 1, "Instances": [inst]}]}, arg("--query"))
    else:
        emit({"AutoScalingGroups": [{"AutoScalingGroupName": "imageflow-asg", "DesiredCapacity": 1, "Instances": [{"InstanceId": "i-1", "LifecycleState": "InService"}]}]}, arg("--query"))
elif SERVICE == "autoscaling" and CMD == "update-auto-scaling-group":
    print("{}")
elif SERVICE == "ec2" and CMD == "terminate-instances":
    print(json.dumps({"TerminatingInstances": [{"InstanceId": "i-old-1", "CurrentState": {"Name": "shutting-down"}}]}))
elif SERVICE == "ec2" and CMD == "describe-instances":
    # The script's cosmetic query uses a flatten + projection the mini-query
    # parser can't handle — just answer with the plain instance line.
    print("i-new-2\trunning")

else:
    sys.stderr.write(f"unexpected: {SERVICE} {CMD}\n")
    sys.exit(2)
FAKE
chmod +x "$FAKE_BIN/aws"

# ── Fake kubectl CLI (case on "sub:target" so every invocation exits 0) ──
cat > "$FAKE_BIN/kubectl" <<'FAKE'
#!/usr/bin/env bash
# shellcheck shell=bash
sub="${1:-}"; target="${2:-}"
case "$sub:$target" in
    get:nodes)  printf '%s\n' 'node1 Ready' ;;
    # Pod-name jsonpath: when -o jsonpath asks for the pod name, print just it.
    get:pods)
        if printf '%s' "$*" | grep -q 'jsonpath'; then
            printf '%s\n' 'imageflow-7c9d5f6b8f-abcde'
        else
            printf '%s\n' 'imageflow-7c9d5f6b8f-abcde 1/1 Running'
        fi
        ;;
    get:hpa)    printf '%s\n' 'imageflow Deployment/imageflow 7%/70% 1 3 1 22h' ;;
    get:deploy) printf '%s\n' 'imageflow 1/1 1 1 22h' ;;
    delete:pod) printf '%s\n' 'pod "imageflow-7c9d5f6b8f-abcde" deleted' ;;
    rollout:status) printf '%s\n' 'deployment "imageflow" successfully rolled out' ;;
    scale:deploy) printf '%s\n' 'deployment.apps/imageflow scaled' ;;
    *) echo "unexpected: $*" >&2; exit 2 ;;
esac
exit 0
FAKE
chmod +x "$FAKE_BIN/kubectl"
export PATH="$FAKE_BIN:$PATH"

# ── 1. Syntax ────────────────────────────────────────────────────────
if bash -n "$RELIABILITY"; then pass "bash -n syntax check"; else fail "bash -n syntax check"; fi

# ── 2. --help exits 0 ────────────────────────────────────────────────
set +e; "$RELIABILITY" --help >/dev/null 2>&1; c=$?; set -e
[ "$c" -eq 0 ] && pass "--help exits 0 (got $c)" || fail "--help exits 0 (got $c)"

# ── 3. No command / unknown command / unknown chaos target exit 2 ─────
set +e
"$RELIABILITY" >/dev/null 2>&1; c1=$?
"$RELIABILITY" bogus >/dev/null 2>&1; c2=$?
"$RELIABILITY" chaos nope >/dev/null 2>&1; c3=$?
"$RELIABILITY" chaos >/dev/null 2>&1; c4=$?
set -e
[ "$c1" -eq 2 ] && [ "$c2" -eq 2 ] && [ "$c3" -eq 2 ] && [ "$c4" -eq 2 ] \
    && pass "usage errors exit 2 (got $c1/$c2/$c3/$c4)" \
    || fail "usage errors exit 2 (got $c1/$c2/$c3/$c4)"

# ── 4. backup creates dir + manifest, exits 0 ────────────────────────
set +e
out="$("$RELIABILITY" backup 2>&1)"
c=$?
set -e
bk="$(find "$TEST_BACKUP_DIR" -maxdepth 1 -type d -name 'cloud-*' -print | sort | tail -1 || true)"
if [ "$c" -eq 0 ] && [ -n "$bk" ] && [ -f "$bk/dynamodb.jsonl" ] && [ -f "$bk/manifest.txt" ]; then
    pass "backup creates manifest + jsonl, exits 0 (got $c)"
else
    fail "backup creates manifest + jsonl, exits 0 (got $c: $(printf '%s' "$out" | tail -2))"
fi

# ── 5. backup with aws down exits 1 ──────────────────────────────────
set +e
IMAGEFLOW_FAKE_AWS_MODE=down "$RELIABILITY" backup >/dev/null 2>&1
c=$?
set -e
[ "$c" -eq 1 ] && pass "backup with aws down exits 1 (got $c)" || fail "backup with aws down exits 1 (got $c)"

# ── 6. restore from the just-made backup exits 0 ─────────────────────
set +e
out="$("$RELIABILITY" restore 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "restore complete"; then
    pass "restore exits 0 and completes (got $c)"
else
    fail "restore exits 0 and completes (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 7. restore with no backups exits 1 ───────────────────────────────
set +e
out="$(IMAGEFLOW_BACKUP_DIR="$(mktemp -d)/empty" "$RELIABILITY" restore 2>&1)"
c=$?
set -e
[ "$c" -eq 1 ] && pass "restore with no backups exits 1 (got $c)" || fail "restore with no backups exits 1 (got $c)"

# ── 8. drill (full round trip) exits 0 ───────────────────────────────
set +e
out="$("$RELIABILITY" drill 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "RTO (measured restore time)"; then
    pass "drill exits 0 and reports RTO (got $c)"
else
    fail "drill exits 0 and reports RTO (got $c: $(printf '%s' "$out" | tail -4))"
fi

# ── 9. chaos kill-pod exits 0 (fake kubectl) ─────────────────────────
set +e
out="$("$RELIABILITY" chaos kill-pod 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "recovery in"; then
    pass "chaos kill-pod exits 0 with recovery time (got $c)"
else
    fail "chaos kill-pod exits 0 with recovery time (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 9b. chaos kill-instance exits 0 (ASG reconciles a replacement) ──
set +e
out="$(IMAGEFLOW_FAKE_AWS_MODE=killinst "$RELIABILITY" chaos kill-instance 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "ASG reconciled: i-old-1 → i-new-2"; then
    pass "chaos kill-instance exits 0 with reconciled replacement (got $c)"
else
    fail "chaos kill-instance exits 0 with reconciled replacement (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 10. chaos kill-api: without a running API exits 1 ────────────────
set +e
"$RELIABILITY" chaos kill-api >/dev/null 2>&1
c=$?
set -e
[ "$c" -eq 1 ] && pass "chaos kill-api with no API exits 1 (got $c)" || fail "chaos kill-api with no API exits 1 (got $c)"

# ── 10b. chaos kill-api full round trip against a real uvicorn ───────
# Starts a real API, kills it via the script, and verifies it restarts
# (mirrors test_deploy.sh's live-server approach).
VENV_UVICORN="$REPO_ROOT/.venv/bin/uvicorn"
if [ ! -x "$VENV_UVICORN" ]; then
    fail "chaos kill-api live round trip skipped (venv uvicorn not found)"
else
    mkdir -p "$REPO_ROOT/data"
    rm -f "$REPO_ROOT/data/api.pid" "$REPO_ROOT/data/api.log"
    "$VENV_UVICORN" app.main:app --host 127.0.0.1 --port 8000 >>"$REPO_ROOT/data/api.log" 2>&1 &
    API_PID=$!
    echo "$API_PID" > "$REPO_ROOT/data/api.pid"
    sleep 4
    # Use a file (not a pipe) for capture — the restarted uvicorn holds the
    # pipe open, which would hang a $() command substitution.
    set +e
    IMAGEFLOW_API_URL=http://127.0.0.1:8000 "$RELIABILITY" chaos kill-api >/tmp/killapi-test.log 2>&1 </dev/null
    c=$?
    set -e
    out="$(cat /tmp/killapi-test.log)"
    # deploy.sh restarts the API; capture the new pid so cleanup can stop it.
    [ -f "$REPO_ROOT/data/api.pid" ] && API_PID="$(cat "$REPO_ROOT/data/api.pid")"
    if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "API recovered"; then
        pass "chaos kill-api live round trip exits 0 (got $c)"
    else
        fail "chaos kill-api live round trip exits 0 (got $c: $(printf '%s' "$out" | tail -4))"
    fi
fi

# ── 11. chaos fail-image exits 0 (FAILED → fix → PROCESSED) ──────────
set +e
out="$(IMAGEFLOW_FAKE_AWS_MODE=failed "$RELIABILITY" chaos fail-image 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "reprocessed to PROCESSED"; then
    pass "chaos fail-image exits 0 after retry (got $c)"
else
    fail "chaos fail-image exits 0 after retry (got $c: $(printf '%s' "$out" | tail -4))"
fi

# ── 12. scaling exits 0 (fake kubectl + fake aws) ────────────────────
set +e
out="$("$RELIABILITY" scaling 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "ASG imageflow-asg"; then
    pass "scaling exits 0 and reports ASG (got $c)"
else
    fail "scaling exits 0 and reports ASG (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 13. reconcile reports drift (desired 1 vs 0 instances) ───────────
set +e
out="$(IMAGEFLOW_FAKE_AWS_MODE=drift "$RELIABILITY" reconcile 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "DRIFT"; then
    pass "reconcile detects drift in report mode (got $c)"
else
    fail "reconcile detects drift in report mode (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 14. reconcile --apply exits 0 and applies correction ─────────────
set +e
out="$(IMAGEFLOW_FAKE_AWS_MODE=drift "$RELIABILITY" reconcile --apply 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "→ applied"; then
    pass "reconcile --apply corrects drift (got $c)"
else
    fail "reconcile --apply corrects drift (got $c: $(printf '%s' "$out" | tail -3))"
fi

# ── 15. reconcile with converged ASG exits 0, no drift ───────────────
set +e
out="$("$RELIABILITY" reconcile 2>&1)"
c=$?
set -e
if [ "$c" -eq 0 ] && printf '%s' "$out" | grep -q "converged"; then
    pass "reconcile reports converged state (got $c)"
else
    fail "reconcile reports converged state (got $c: $(printf '%s' "$out" | tail -3))"
fi

echo
echo "reliability tests: $passed passed, $failed_tests failed"
[ "$failed_tests" -eq 0 ]
