#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-health-check — verify ImageFlow services are alive (API + Floci).
#
# Usage: ./scripts/health-check.sh [--api-url URL] [--floci-url URL] [--timeout SEC] [--help]
#
# Checks (Phase 4):
#   1. ImageFlow API — GET <API_URL>/health must return HTTP 200 with {"status":"ok"}
#   2. Floci cloud   — <FLOCI_URL> must respond over HTTP
#
# Exits 0 when every check passes, 1 when any fails, 2 on usage errors.
# URLs and timeout can also be set via IMAGEFLOW_API_URL, FLOCI_ENDPOINT_URL,
# and IMAGEFLOW_HEALTH_TIMEOUT (env vars) — flags win over env.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Configuration (env defaults; overridable via flags) ──────────────
API_URL="${IMAGEFLOW_API_URL:-http://127.0.0.1:8000}"
FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"
TIMEOUT="${IMAGEFLOW_HEALTH_TIMEOUT:-3}"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Check that the ImageFlow API (/health) and the local Floci cloud are alive.
Exits non-zero if any check fails.

Options:
  --api-url URL     API base URL       (default: \$IMAGEFLOW_API_URL or http://127.0.0.1:8000)
  --floci-url URL   Floci endpoint URL (default: \$FLOCI_ENDPOINT_URL or http://127.0.0.1:4566)
  --timeout SEC     curl timeout secs  (default: \$IMAGEFLOW_HEALTH_TIMEOUT or 3)
  -h, --help        Show this help and exit.

Exit codes:
  0   all checks healthy
  1   one or more checks failed
  2   usage error
EOF
}

# check_endpoint <name> <url>
# Prints one status line; returns 0 healthy, 1 unhealthy.
check_endpoint() {
    local name="$1" url="$2"
    local code body

    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$url" 2>/dev/null)" || code="000"

    if [ "$code" = "000" ]; then
        error "$name — UNREACHABLE ($url, timeout ${TIMEOUT}s)"
        return 1
    fi

    # For the API, an HTTP 200 is not enough — the liveness body must say ok.
    if [ "$name" = "ImageFlow API" ]; then
        body="$(curl -s --max-time "$TIMEOUT" "$url" 2>/dev/null)" || body=""
        if ! printf '%s' "$body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
            error "$name — DEGRADED ($url returned HTTP $code without status=ok)"
            return 1
        fi
    fi

    info "$name — OK (HTTP $code): $url"
}

main() {
    local failed=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --api-url)
                [ "$#" -ge 2 ] || { error "--api-url requires a value"; usage >&2; return 2; }
                API_URL="$2"; shift 2 ;;
            --floci-url)
                [ "$#" -ge 2 ] || { error "--floci-url requires a value"; usage >&2; return 2; }
                FLOCI_URL="$2"; shift 2 ;;
            --timeout)
                [ "$#" -ge 2 ] || { error "--timeout requires a value"; usage >&2; return 2; }
                case "$2" in
                    ''|0|*[!0-9]*) error "--timeout must be a positive integer"; usage >&2; return 2 ;;
                esac
                TIMEOUT="$2"; shift 2 ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    check_endpoint "ImageFlow API" "$API_URL/health" || failed=$((failed + 1))
    check_endpoint "Floci cloud"   "$FLOCI_URL"      || failed=$((failed + 1))

    if [ "$failed" -gt 0 ]; then
        error "$failed service(s) failed — health check FAILED."
        return 1
    fi
    info "All services healthy."
}

main "$@"
