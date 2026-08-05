#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-observability — report the Phase 13 monitoring stack on Floci.
#
# Usage: ./scripts/observability.sh [--floci-url URL] [--namespace NAME] [--hours N] [--help]
#
# Sections (core sections fail the script; informational ones degrade):
#   1. CloudWatch custom metrics — ImageFlow namespace (Uploads, UploadErrors,
#      ProcessedCount, FailedCount) statistics over the last N hours  [CORE]
#   2. CloudWatch alarms — name + state for every alarm                [CORE]
#   3. EventBridge rules → SNS targets (the demonstrable alert path)   [info]
#   4. CloudWatch log events — /imageflow/api group (if present)       [info]
#   5. SNS topics                                                       [info]
#
# Exits: 0 success · 1 a core section failed (Floci/aws unavailable) · 2 usage.
# Env overrides: FLOCI_ENDPOINT_URL, IMAGEFLOW_CW_NAMESPACE, IMAGEFLOW_CW_HOURS.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"
NAMESPACE="${IMAGEFLOW_CW_NAMESPACE:-ImageFlow}"
HOURS="${IMAGEFLOW_CW_HOURS:-1}"
LOG_GROUP="${IMAGEFLOW_CW_LOG_GROUP:-/imageflow/api}"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Report the ImageFlow observability stack from Floci CloudWatch:
custom metrics (namespace $NAMESPACE), alarm states, EventBridge alert
rules, recent API log events, and SNS topics.

Options:
  --floci-url URL   Floci endpoint URL (default: \$FLOCI_ENDPOINT_URL or http://127.0.0.1:4566)
  --namespace NAME  CloudWatch namespace (default: \$IMAGEFLOW_CW_NAMESPACE or ImageFlow)
  --hours N         metric statistics window in hours (default: \$IMAGEFLOW_CW_HOURS or 1)
  --log-group NAME  CloudWatch log group for API logs (default: \$IMAGEFLOW_CW_LOG_GROUP or /imageflow/api)
  -h, --help        Show this help and exit.

Exit codes:
  0   core telemetry gathered (metrics + alarms)
  1   core telemetry could not be gathered (Floci/aws unavailable)
  2   usage error
EOF
}

# aws_cmd <args...> — every AWS call goes to the local cloud (AGENTS.md §2).
aws_cmd() {
    AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    AWS_DEFAULT_REGION=us-east-1 aws "$@"
}

# ── Section 1 (CORE): CloudWatch custom metrics ──────────────────────
# Returns 1 if the namespace cannot be queried (Floci/aws unavailable).
report_metrics() {
    local start end metric stats ok=0
    start="$(date -u -v-"${HOURS}"H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
             date -u -d "-$HOURS hours" '+%Y-%m-%dT%H:%M:%SZ')"
    end="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    info "CloudWatch metrics (namespace=$NAMESPACE, last ${HOURS}h):"
    for metric in Uploads UploadErrors ProcessedCount FailedCount; do
        if stats="$(aws_cmd cloudwatch get-metric-statistics \
            --namespace "$NAMESPACE" --metric-name "$metric" --statistics Sum \
            --period 300 --start-time "$start" --end-time "$end" \
            --query 'Datapoints[].Sum' --output text 2>/dev/null)"; then
            if [ -n "$stats" ]; then
            info "  $metric  sum=$(echo "$stats" | tr '\t' ',')"
        fi
        else
            info "  $metric  (unavailable)"
            ok=1
        fi
    done
    return "$ok"
}

# ── Section 2 (CORE): CloudWatch alarms ──────────────────────────────
# Returns 1 if describe-alarms fails (Floci/aws unavailable).
report_alarms() {
    local alarms
    info "CloudWatch alarms:"
    if ! alarms="$(aws_cmd cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,StateValue]' --output text 2>/dev/null)"; then
        info "  (unavailable)"
        return 1
    fi
    if [ -z "$alarms" ]; then
        info "  (none configured)"
        return 0
    fi
    while IFS=$'\t' read -r name state; do
        [ -n "$name" ] && info "  $name → $state"
    done <<< "$alarms"
}

# ── Section 3 (info): EventBridge alert rules ────────────────────────
report_rules() {
    local rules arn
    info "EventBridge rules (alerting path):"
    rules="$(aws_cmd events list-rules --query 'Rules[].[Name,State]' --output text 2>/dev/null)" || { info "  (unavailable)"; return 0; }
    if [ -z "$rules" ]; then
        info "  (none)"
        return 0
    fi
    while IFS=$'\t' read -r name state; do
        [ -n "$name" ] || continue
        arn="$(aws_cmd events list-targets-by-rule --rule "$name" --query 'Targets[].Arn' --output text 2>/dev/null)" || arn=""
        info "  $name [$state] → ${arn:-no targets}"
    done <<< "$rules"
}

# ── Section 4 (info): recent API log events ──────────────────────────
report_logs() {
    info "Recent CloudWatch log events (group=$LOG_GROUP):"
    local events
    events="$(aws_cmd logs filter-log-events --log-group-name "$LOG_GROUP" \
        --query 'events[].message' --output text --limit 5 2>/dev/null)" || { info "  (no events / group absent — enable with CLOUDWATCH_LOGS_ENABLED)"; return 0; }
    if [ -z "$events" ]; then
        info "  (no events yet)"
    else
        while IFS= read -r line; do
            [ -n "$line" ] && info "  | $line"
        done <<< "$events"
    fi
}

# ── Section 5 (info): SNS topics ─────────────────────────────────────
report_topics() {
    local topics
    info "SNS topics:"
    topics="$(aws_cmd sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null)" || { info "  (unavailable)"; return 0; }
    if [ -z "$topics" ]; then
        info "  (none)"
    else
        for topic in $topics; do
            info "  $topic"
        done
    fi
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --floci-url)
                [ "$#" -ge 2 ] || { error "--floci-url requires a value"; usage >&2; return 2; }
                FLOCI_URL="$2"; shift 2 ;;
            --namespace)
                [ "$#" -ge 2 ] || { error "--namespace requires a value"; usage >&2; return 2; }
                NAMESPACE="$2"; shift 2 ;;
            --hours)
                [ "$#" -ge 2 ] || { error "--hours requires a value"; usage >&2; return 2; }
                case "$2" in
                    ''|0|*[!0-9]*) error "--hours must be a positive integer"; usage >&2; return 2 ;;
                esac
                HOURS="$2"; shift 2 ;;
            --log-group)
                [ "$#" -ge 2 ] || { error "--log-group requires a value"; usage >&2; return 2; }
                LOG_GROUP="$2"; shift 2 ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    if ! command -v aws >/dev/null 2>&1; then
        error "missing prerequisite: aws CLI (see docs/setup.md)"
        return 1
    fi

    # Core sections: metrics + alarms. If Floci is unreachable these fail.
    if ! report_metrics; then
        error "could not read CloudWatch metrics — is Floci running at $FLOCI_URL?"
        return 1
    fi
    if ! report_alarms; then
        error "could not read CloudWatch alarms — is Floci running at $FLOCI_URL?"
        return 1
    fi

    # Informational sections degrade gracefully.
    report_rules
    report_logs
    report_topics

    info "observability report complete."
}

main "$@"
