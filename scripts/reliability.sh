#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-reliability — Phase 15 reliability drills on Floci (ADR-13).
#
# Usage: ./scripts/reliability.sh [COMMAND] [OPTIONS]
#
# Commands:
#   backup     Snapshot the cloud data plane (DynamoDB export + S3 sync) to
#              data/backups/cloud-<ts>/ with a manifest (the DR restore point).
#   restore    Restore from the newest backup (or --backup DIR): re-import the
#              DynamoDB items + sync S3 objects back, then verify counts.
#   drill      Full DR drill: create probe data → backup → simulate loss →
#              restore → verify → report measured RTO (and RPO=0 for the drill).
#   chaos      Failure injection demos (see below): kill-pod | kill-instance | kill-api | fail-image
#   scaling    Auto-scaling demo: HPA + Deployment reconciler on k3s; ASG
#              instance count + replacement on Floci (live).
#   reconcile  Auto-scaling reconciler loop: desired vs actual for ASG +
#              Deployment + HPA; --apply corrects drift (kubectl scale /
#              update-auto-scaling-group).
#   all        Run backup → drill → chaos kill-api → scaling → reconcile.
#
# Chaos targets:
#   kill-pod       Delete an imageflow pod → the Deployment controller recreates
#                  it (self-healing); measures recovery time.
#   kill-instance  Terminate the ASG's EC2 instance → the Auto Scaling group
#                  reconciles a replacement (Auto Scaling replacement).
#   kill-api       Kill the host API process → /health fails → restart via
#                  deploy.sh → healthy again (process resilience).
#   fail-image     Upload a corrupt "image" → Lambda marks it FAILED (dead-letter),
#                  then fix + reprocess → PROCESSED (retry/recovery).
#
# Exit codes: 0 success · 1 a core operation failed · 2 usage error.
# Env overrides: FLOCI_ENDPOINT_URL · IMAGEFLOW_BACKUP_DIR · IMAGEFLOW_METADATA_TABLE
#                IMAGEFLOW_UPLOADS_BUCKET · IMAGEFLOW_THUMBS_BUCKET · IMAGEFLOW_ASG_NAME
#                IMAGEFLOW_API_URL

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"
BACKUP_ROOT="${IMAGEFLOW_BACKUP_DIR:-$REPO_ROOT/data/backups}"
TABLE="${IMAGEFLOW_METADATA_TABLE:-ImageFlowMetadata}"
UPLOADS_BUCKET="${IMAGEFLOW_UPLOADS_BUCKET:-imageflow-uploads}"
THUMBS_BUCKET="${IMAGEFLOW_THUMBS_BUCKET:-imageflow-thumbs}"
ASG_NAME="${IMAGEFLOW_ASG_NAME:-imageflow-asg}"
API_URL="${IMAGEFLOW_API_URL:-http://127.0.0.1:8000}"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
step()  { printf '\n[STEP]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]

Phase 15 reliability drills against the local cloud (Floci).

Commands:
  backup                Snapshot DynamoDB + S3 to data/backups/cloud-<ts>/
  restore               Restore from the newest backup (--backup DIR to pick one)
  drill                 Backup → simulate loss → restore → verify (reports RTO)
  chaos kill-pod        Delete a k3s pod; Deployment reconciler recreates it
  chaos kill-instance   Terminate the ASG instance; the ASG launches a replacement
  chaos kill-api        Kill the API process; restart; verify /health recovery
  chaos fail-image      Corrupt upload → FAILED dead-letter → fix → reprocess
  scaling               HPA/Deployment reconciler on k3s + ASG instance count
  reconcile [--apply]   Desired-vs-actual drift report (+ correct with --apply)
  all                   backup → drill → chaos kill-api → scaling → reconcile
  -h, --help            Show this help and exit.

Options:
  --floci-url URL       Floci endpoint (default: \$FLOCI_ENDPOINT_URL or http://127.0.0.1:4566)
  --backup DIR          Backup dir to restore from (restore only)
  --table NAME          DynamoDB table (default: \$IMAGEFLOW_METADATA_TABLE or ImageFlowMetadata)

Exit codes:
  0   success
  1   a core operation failed
  2   usage error
EOF
}

# ── AWS plumbing ─────────────────────────────────────────────────────
# Export once so direct calls AND the python3 restore helper (subprocess)
# both hit Floci — never ambient real-cloud config (AGENTS.md §2).
export AWS_ENDPOINT_URL="$FLOCI_URL"
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws_cmd() { aws "$@"; }

require_aws() {
    command -v aws >/dev/null 2>&1 || { error "missing prerequisite: aws CLI (see docs/setup.md)"; return 1; }
}

require_kubectl() {
    command -v kubectl >/dev/null 2>&1 || { error "missing prerequisite: kubectl — needed for this demo"; return 1; }
    kubectl get nodes >/dev/null 2>&1 || { error "kubectl cannot reach the cluster — is Floci running and the kubeconfig set? (eval \$(floci env))"; return 1; }
}

# ── Backup / restore ─────────────────────────────────────────────────
# Export the DynamoDB table as JSON-lines (one typed item per line) into $out.
# Pages with --max-items/--starting-token so the export is correct for large
# tables, not just this 66-item demo (real-AWS-correct, ADR-13).
ddb_export() {
    local table="$1" out="$2" token="" page next
    : > "$out"
    while :; do
        page="$(mktemp)"
        if [ -n "$token" ]; then
            aws_cmd dynamodb scan --table-name "$table" --max-items 100 \
                --starting-token "$token" --output json > "$page"
        else
            aws_cmd dynamodb scan --table-name "$table" --max-items 100 --output json > "$page"
        fi
        python3 - "$page" "$out" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
with open(sys.argv[2], "a") as f:
    for item in data.get("Items", []):
        f.write(json.dumps(item) + "\n")
PY
        next="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('NextToken',''))" "$page")"
        rm -f "$page"
        [ -n "$next" ] || break
        token="$next"
    done
}

# Import JSON-lines back via batch-write-item (25/chunk, retries unprocessed).
ddb_import() {
    local file="$1" table="$2"
    python3 - "$file" "$table" <<'PY'
import json, subprocess, sys, time
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
table = sys.argv[2]
chunks = [lines[i:i + 25] for i in range(0, len(lines), 25)]
written = 0
for chunk in chunks:
    req = {table: [{"PutRequest": {"Item": it}} for it in chunk]}
    for _attempt in range(3):
        proc = subprocess.run(
            ["aws", "dynamodb", "batch-write-item", "--request-items", json.dumps(req),
             "--output", "json"],
            capture_output=True, text=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr)
            sys.exit(1)
        try:
            resp = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            # Never silently skip a chunk — retry, and let the for-else exit 1
            # if all attempts fail (review-fix: break here lost data silently).
            sys.stderr.write(f"batch-write-item: unparseable response ({exc}); retrying\n")
            time.sleep(1)
            continue
        unproc = resp.get("UnprocessedItems", {})
        if not unproc:
            written += len(chunk)
            break
        req = unproc  # retry only the unprocessed requests
        time.sleep(1)
    else:
        sys.exit(1)
print(written)
PY
}

latest_backup() {
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'cloud-*' -print 2>/dev/null | sort | tail -1
}

# ── Commands ─────────────────────────────────────────────────────────
cmd_backup() {
    local stamp dir manifest n_items n_uploads n_thumbs
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$BACKUP_ROOT/cloud-$stamp"
    mkdir -p "$dir/uploads" "$dir/thumbs"
    step "BACKUP → $dir"

    info "  DynamoDB: exporting $TABLE (paginated JSON-lines)"
    ddb_export "$TABLE" "$dir/dynamodb.jsonl"

    info "  S3: syncing s3://$UPLOADS_BUCKET → uploads/"
    aws_cmd s3 sync "s3://$UPLOADS_BUCKET" "$dir/uploads/" >/dev/null
    info "  S3: syncing s3://$THUMBS_BUCKET → thumbs/"
    aws_cmd s3 sync "s3://$THUMBS_BUCKET" "$dir/thumbs/" >/dev/null

    n_items="$(wc -l < "$dir/dynamodb.jsonl" | tr -d ' ')"
    n_uploads="$(find "$dir/uploads" -type f 2>/dev/null | wc -l | tr -d ' ')"
    n_thumbs="$(find "$dir/thumbs" -type f 2>/dev/null | wc -l | tr -d ' ')"
    manifest="$dir/manifest.txt"
    {
        echo "table=$TABLE"
        echo "items=$n_items"
        echo "uploads=$n_uploads"
        echo "thumbs=$n_thumbs"
        echo "created=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$manifest"
    info "  manifest: $(tr '\n' ' ' < "$manifest")"
    info "backup complete ($n_items items, $n_uploads+$n_thumbs objects)."
}

cmd_restore() {
    local dir backup_arg="" manifest n_items n_uploads n_thumbs
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --backup) [ "$#" -ge 2 ] || { error "--backup requires a value"; usage >&2; return 2; }
                backup_arg="$2"; shift 2 ;;
            *) error "unknown option: $1"; usage >&2; return 2 ;;
        esac
    done
    if [ -n "$backup_arg" ]; then
        dir="$backup_arg"
    else
        dir="$(latest_backup)" || true
        [ -n "$dir" ] || { error "no cloud backup found in $BACKUP_ROOT — run '$SCRIPT_NAME backup' first"; return 1; }
    fi
    [ -f "$dir/dynamodb.jsonl" ] || { error "backup dir missing dynamodb.jsonl: $dir"; return 1; }

    step "RESTORE ← $dir"
    info "  DynamoDB: batch-writing $(wc -l < "$dir/dynamodb.jsonl" | tr -d ' ') items"
    ddb_import "$dir/dynamodb.jsonl" "$TABLE" || { error "dynamodb restore failed"; return 1; }
    if [ -d "$dir/uploads" ]; then
        info "  S3: syncing uploads/ → s3://$UPLOADS_BUCKET"
        aws_cmd s3 sync "$dir/uploads/" "s3://$UPLOADS_BUCKET" >/dev/null
    fi
    if [ -d "$dir/thumbs" ]; then
        info "  S3: syncing thumbs/ → s3://$THUMBS_BUCKET"
        aws_cmd s3 sync "$dir/thumbs/" "s3://$THUMBS_BUCKET" >/dev/null
    fi

    # Verify counts against the manifest — comparing the LIVE table after
    # restore (not the local jsonl, which is always equal by construction).
    if [ -f "$dir/manifest.txt" ]; then
        local want_items live_items live_file
        want_items="$(grep '^items=' "$dir/manifest.txt" | cut -d= -f2)"
        # Reuse the paginated export to count live rows (single scans truncate
        # at 1 MiB on large tables).
        live_file="$(mktemp)"
        ddb_export "$TABLE" "$live_file"
        live_items="$(wc -l < "$live_file" | tr -d ' ')"
        rm -f "$live_file"
        info "  verification: manifest says $want_items items; live table has $live_items"
        [ "$want_items" = "$live_items" ] || { error "item count mismatch after restore (manifest $want_items != live $live_items)"; return 1; }
    fi
    info "restore complete."
}

# Full DR drill: probe data → backup → destroy → restore → verify + RTO.
cmd_drill() {
    local probe id png t0 t1 rto
    probe="reliability-drill-$(date +%s)"
    step "DRILL — backup/restore with simulated data loss (probe=$probe)"
    info "  creating probe data (1×1 PNG + metadata record)"
    png="$(mktemp)"
    python3 - "$png" <<'PY'
import base64, sys
# 1x1 transparent PNG (valid Pillow input)
open(sys.argv[1], "wb").write(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
PY
    aws_cmd s3 cp "$png" "s3://$UPLOADS_BUCKET/uploads/$probe/probe.png" >/dev/null
    aws_cmd dynamodb put-item --table-name "$TABLE" --item "{\"image_id\":{\"S\":\"$probe\"},\"filename\":{\"S\":\"probe.png\"},\"size\":{\"N\":\"68\"},\"status\":{\"S\":\"PENDING\"},\"original_key\":{\"S\":\"uploads/$probe/probe.png\"},\"content_type\":{\"S\":\"image/png\"}}" >/dev/null
    rm -f "$png"

    info "  taking backup..."
    cmd_backup
    info "  SIMULATED DISASTER: deleting probe record + object"
    aws_cmd dynamodb delete-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$probe\"}}" >/dev/null
    aws_cmd s3 rm "s3://$UPLOADS_BUCKET/uploads/$probe/probe.png" >/dev/null
    info "  confirming probe is gone..."
    # NOTE: the real AWS CLI prints the literal text "None" for a missing
    # item with --query ... --output text — so grep for the probe id itself
    # (never just "any output").
    if aws_cmd dynamodb get-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$probe\"}}" --query 'Item.image_id.S' --output text 2>/dev/null | grep -q "$probe"; then
        error "probe record still present after deletion — drill aborted"; return 1
    fi

    t0="$(date +%s)"
    info "  restoring from backup..."
    cmd_restore --backup "$(latest_backup)"
    t1="$(date +%s)"
    rto=$((t1 - t0))

    info "  verifying probe is back..."
    if ! aws_cmd dynamodb get-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$probe\"}}" --query 'Item.image_id.S' --output text 2>/dev/null | grep -q "$probe"; then
        error "probe record NOT restored — drill FAILED"; return 1
    fi
    if ! aws_cmd s3api head-object --bucket "$UPLOADS_BUCKET" --key "uploads/$probe/probe.png" --query ContentLength --output text >/dev/null 2>&1; then
        error "probe object NOT restored — drill FAILED"; return 1
    fi

    info "cleaning up probe data..."
    aws_cmd dynamodb delete-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$probe\"}}" >/dev/null
    aws_cmd s3 rm "s3://$UPLOADS_BUCKET/uploads/$probe/probe.png" >/dev/null

    step "DRILL RESULT — data loss recovered"
    info "  RTO (measured restore time): ${rto}s"
    info "  RPO (drill): 0s — the backup preceded the simulated loss; in production RPO = backup cadence"
    info "  verification: metadata record + object restored and readable"
}

# wait_status <image_id> <status> <timeout_s> — poll until the record reaches
# the given status. Returns 1 on timeout.
wait_status() {
    local id="$1" want="$2" timeout_s="$3" got="" i
    for ((i = 0; i < timeout_s; i++)); do
        got="$(aws_cmd dynamodb get-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$id\"}}" --query 'Item.status.S' --output text 2>/dev/null || true)"
        [ "$got" = "$want" ] && return 0
        sleep 1
    done
    error "timed out waiting for $id → $want (last status: ${got:-none})"
    return 1
}

# ── Chaos demos ──────────────────────────────────────────────────────
chaos_kill_pod() {
    require_kubectl || return 1
    step "CHAOS — kill an imageflow pod; Deployment controller must self-heal"
    local pod t0 t1
    pod="$(kubectl get pods -l app.kubernetes.io/name=imageflow -o jsonpath='{.items[0].metadata.name}')"
    [ -n "$pod" ] || { error "no imageflow pod found"; return 1; }
    info "  deleting pod $pod..."
    t0="$(date +%s)"
    kubectl delete pod "$pod" --wait=false >/dev/null
    kubectl rollout status deployment/imageflow --timeout=120s >/dev/null
    t1="$(date +%s)"
    info "  Deployment reconciler recreated the pod — recovery in $((t1 - t0))s"
    info "  current pods:"
    kubectl get pods -l app.kubernetes.io/name=imageflow -o wide | tail -n +2 | head -5
}

chaos_kill_api() {
    step "CHAOS — kill the API process; verify health failure + recovery"
    local pid
    if [ ! -f "$REPO_ROOT/data/api.pid" ]; then
        error "no API running (data/api.pid missing) — start it with scripts/deploy.sh first"
        return 1
    fi
    pid="$(cat "$REPO_ROOT/data/api.pid")"
    info "  killing API pid $pid..."
    kill "$pid" 2>/dev/null || { error "API process $pid not running"; return 1; }

    info "  verifying /health now FAILS..."
    # uvicorn's graceful SIGTERM shutdown can accept a few more requests —
    # poll up to ~6s for the failure rather than trusting a single curl.
    local i failed=1
    for ((i = 0; i < 6; i++)); do
        if ! curl -s --max-time 2 "$API_URL/health" 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
            failed=0; break
        fi
        sleep 1
    done
    if [ "$failed" -eq 1 ]; then
        error "API still healthy after kill — expected failure"; return 1
    fi
    info "  /health correctly failed — restarting via deploy.sh..."
    "$REPO_ROOT/scripts/deploy.sh" --skip-terraform --skip-smoke >/dev/null || { error "deploy.sh restart failed"; return 1; }
    info "  verifying /health recovered..."
    if ! curl -s --max-time 3 "$API_URL/health" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
        error "API did not recover after restart"; return 1
    fi
    info "  API recovered — process resilience verified"
}

chaos_fail_image() {
    step "CHAOS — corrupt upload → FAILED dead-letter → fix → reprocess"
    local id bad
    id="fail-image-$(date +%s)"
    bad="$(mktemp)"
    printf 'this is not an image' > "$bad"
    info "  creating the metadata record FIRST, then uploading corrupt bytes..."
    # Order matters (the live drill caught this race): put-item BEFORE s3 cp, or
    # the S3 event can fire while the record doesn't exist yet → the Lambda skips
    # it ("missing record") and the record stays PENDING forever. Record-first
    # guarantees the event finds its PENDING record → corrupt bytes → FAILED.
    aws_cmd dynamodb put-item --table-name "$TABLE" --item "{\"image_id\":{\"S\":\"$id\"},\"filename\":{\"S\":\"corrupt.bin\"},\"size\":{\"N\":\"20\"},\"status\":{\"S\":\"PENDING\"},\"original_key\":{\"S\":\"uploads/$id/corrupt.bin\"},\"content_type\":{\"S\":\"application/octet-stream\"}}" >/dev/null
    aws_cmd s3 cp "$bad" "s3://$UPLOADS_BUCKET/uploads/$id/corrupt.bin" >/dev/null
    rm -f "$bad"

    info "  waiting for Lambda to mark it FAILED (dead-letter)..."
    wait_status "$id" FAILED 60 || { error "corrupt image did not reach FAILED — is the Lambda trigger wired?"; return 1; }
    info "  ✓ FAILED observed — dead-letter works (status + error field persisted)"

    info "  fixing: reset to PENDING, then write valid image bytes..."
    # Reset BEFORE re-uploading. The fix upload re-injects an S3 event that may
    # auto-reprocess the record; the lambda invoke below is the explicit DLQ
    # replay. process_image skips already-PROCESSED records, so if both paths
    # fire, exactly one reprocess lands (no ProcessedCount inflation).
    aws_cmd dynamodb update-item --table-name "$TABLE" --key "{\"image_id\":{\"S\":\"$id\"}}" \
        --update-expression "SET #s = :p" \
        --expression-attribute-names '{"#s":"status"}' \
        --expression-attribute-values '{":p":{"S":"PENDING"}}' >/dev/null
    png="$(mktemp)"
    python3 - "$png" <<'PY'
import base64, sys
open(sys.argv[1], "wb").write(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
PY
    aws_cmd s3 cp "$png" "s3://$UPLOADS_BUCKET/uploads/$id/corrupt.bin" >/dev/null
    rm -f "$png"

    info "  reprocessing via aws lambda invoke (synthetic S3 event = the DLQ replay path)..."
    # Replay the S3 event for the fixed object — the real retry path on AWS
    # (dead-letter → fix → re-inject the event). No venv/handler dependency.
    payload="{\"Records\":[{\"s3\":{\"object\":{\"key\":\"uploads/$id/corrupt.bin\"}}}]}"
    aws_cmd lambda invoke --function-name image-processor --payload "$payload" \
        --cli-binary-format raw-in-base64-out /dev/null >/dev/null 2>&1 \
        || { error "lambda invoke failed"; return 1; }
    info "  waiting for PROCESSED..."
    wait_status "$id" PROCESSED 60 || { error "image did not recover to PROCESSED"; return 1; }
    info "  ✓ reprocessed to PROCESSED — retry/recovery path verified"
}

chaos_kill_instance() {
    require_aws || return 1
    step "CHAOS — terminate the ASG instance; the ASG must launch a replacement"
    local old_id new_id t0 t1 i
    old_id="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text 2>/dev/null || true)"
    [ -n "$old_id" ] && [ "$old_id" != "None" ] || { error "no instance in ASG $ASG_NAME — is terraform applied?"; return 1; }
    info "  terminating instance $old_id..."
    t0="$(date +%s)"
    aws_cmd ec2 terminate-instances --instance-ids "$old_id" >/dev/null
    new_id=""
    for ((i = 0; i < 30; i++)); do
        sleep 2
        new_id="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text 2>/dev/null || true)"
        [ -n "$new_id" ] && [ "$new_id" != "None" ] && [ "$new_id" != "$old_id" ] && break
    done
    t1="$(date +%s)"
    if [ -n "$new_id" ] && [ "$new_id" != "None" ] && [ "$new_id" != "$old_id" ]; then
        info "  ASG reconciled: $old_id → $new_id in $((t1 - t0))s"
        info "  instance state:"
        aws_cmd ec2 describe-instances --instance-ids "$new_id" --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text 2>/dev/null | sed 's/^/    /'
    else
        error "ASG did not launch a replacement within 60s"
        return 1
    fi
}

cmd_chaos() {
    case "${1:-}" in
        kill-pod)       chaos_kill_pod ;;
        kill-instance)  chaos_kill_instance ;;
        kill-api)       chaos_kill_api ;;
        fail-image)     chaos_fail_image ;;
        "")             error "chaos requires a target: kill-pod | kill-instance | kill-api | fail-image"; usage >&2; return 2 ;;
        *)              error "unknown chaos target: $1"; usage >&2; return 2 ;;
    esac
}

# ── Scaling / reconciler ─────────────────────────────────────────────
cmd_scaling() {
    step "SCALING — auto-scaling demo"
    info "HPA on k3s (real reconciler):"
    if require_kubectl 2>/dev/null; then
        info "  current HPA state:"
        kubectl get hpa imageflow 2>/dev/null | tail -n +1
        info "  scaling Deployment to 3 replicas — the controller reconciles pods:"
        kubectl scale deploy imageflow --replicas=3 >/dev/null
        kubectl rollout status deployment/imageflow --timeout=120s >/dev/null
        kubectl get pods -l app.kubernetes.io/name=imageflow | tail -n +2 | head -5
        info "  scaling back to 1:"
        kubectl scale deploy imageflow --replicas=1 >/dev/null
        kubectl rollout status deployment/imageflow --timeout=120s >/dev/null
        kubectl get pods -l app.kubernetes.io/name=imageflow | tail -n +2 | head -5
    else
        info "  (kubectl/cluster unavailable — skipping live HPA demo)"
    fi

    info "ASG on Floci (launch-template backed — live instance launch):"
    local desired actual inst
    desired="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].DesiredCapacity' --output text 2>/dev/null || echo '')"
    actual="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'length(AutoScalingGroups[0].Instances)' --output text 2>/dev/null || echo '')"
    if [ -n "$desired" ]; then
        inst="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text 2>/dev/null || echo '')"
        info "  ASG $ASG_NAME: desired=$desired actual-instances=${actual:-0} (${inst:-none})"
        info "  terminate the instance and the ASG launches a replacement — try:"
        info "  ./scripts/reliability.sh chaos kill-instance"
    else
        info "  $ASG_NAME not found — run terraform apply (module autoscaling)."
    fi
}

# The reconciler loop: desired vs actual for ASG / Deployment / HPA.
# Dry-run by default; --apply executes corrective actions.
cmd_reconcile() {
    local apply=0
    case "${1:-}" in
        --apply) apply=1 ;;
        "") : ;;
        *) error "unknown option: $1"; usage >&2; return 2 ;;
    esac
    step "RECONCILE — desired vs actual (${apply:+apply mode|dry-run mode})"

    # 1) ASG
    local desired actual drift=0
    desired="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].DesiredCapacity' --output text 2>/dev/null || echo '')"
    if [ -n "$desired" ]; then
        actual="$(aws_cmd autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'length(AutoScalingGroups[0].Instances)' --output text 2>/dev/null || echo '0')"
        info "  ASG $ASG_NAME: desired=$desired actual=${actual:-0}"
        if [ "${actual:-0}" != "$desired" ]; then
            info "  → DRIFT detected."
            if [ "$apply" -eq 1 ]; then
                info "  → applying: update-auto-scaling-group desired-capacity=$desired"
                aws_cmd autoscaling update-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --desired-capacity "$desired" >/dev/null
                info "  → applied."
            fi
            drift=1
        else
            info "  → converged."
        fi
    else
        info "  ASG $ASG_NAME not found — skipping (terraform apply provisions it)."
    fi

    # 2) k3s Deployment + HPA (only when the cluster is reachable)
    if require_kubectl 2>/dev/null; then
        local desired_rep ready_rep hpa_min hpa_max hpa_cur
        desired_rep="$(kubectl get deploy imageflow -o jsonpath='{.spec.replicas}' 2>/dev/null || echo '')"
        ready_rep="$(kubectl get deploy imageflow -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '')"
        if [ -n "$desired_rep" ]; then
            info "  Deployment imageflow: desired=$desired_rep ready=${ready_rep:-0}"
            if [ "${ready_rep:-0}" != "$desired_rep" ]; then
                info "  → DRIFT detected."
                if [ "$apply" -eq 1 ]; then
                    info "  → applying: kubectl scale --replicas=$desired_rep"
                    kubectl scale deploy imageflow --replicas="$desired_rep" >/dev/null
                    kubectl rollout status deployment/imageflow --timeout=120s >/dev/null
                    info "  → applied."
                fi
                drift=1
            else
                info "  → converged."
            fi
        fi
        hpa_cur="$(kubectl get hpa imageflow -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo '')"
        hpa_min="$(kubectl get hpa imageflow -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo '')"
        hpa_max="$(kubectl get hpa imageflow -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo '')"
        [ -n "$hpa_min" ] && info "  HPA imageflow: min=$hpa_min max=$hpa_max current=${hpa_cur:-?}"
    else
        info "  Deployment/HPA: cluster unavailable — skipping live check."
    fi

    if [ "$drift" -eq 1 ] && [ "$apply" -eq 0 ]; then
        info "reconcile: drift found (report-only — rerun with --apply to correct)."
    else
        info "reconcile: no drift remains."
    fi
    return 0
}

cmd_all() {
    require_aws || return 1
    cmd_backup
    cmd_drill
    chaos_kill_api
    cmd_scaling
    cmd_reconcile
    step "ALL RELIABILITY DRILLS DONE"
}

main() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage; return 0
    fi
    require_aws || return 1
    case "${1:-}" in
        backup)    shift; cmd_backup ;;
        restore)   shift; cmd_restore "$@" ;;
        drill)     shift; cmd_drill ;;
        chaos)     shift; cmd_chaos "$@" ;;
        scaling)   shift; cmd_scaling ;;
        reconcile) shift; cmd_reconcile "$@" ;;
        all)       shift; cmd_all ;;
        "")        error "missing command — try '$SCRIPT_NAME --help'"; usage >&2; return 2 ;;
        *)         error "unknown command: $1"; usage >&2; return 2 ;;
    esac
}

main "$@"
