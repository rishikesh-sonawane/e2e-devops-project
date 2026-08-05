#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-deploy — deploy the ImageFlow stack to the local Floci cloud.
#
# Usage: ./scripts/deploy.sh [OPTIONS]
#
# Pipeline (Phase 4):
#   1. Prerequisites — terraform, curl, reachable Floci
#   2. Terraform — init + apply in terraform/            (skip: --skip-terraform)
#   3. API — start uvicorn from the repo venv            (skip: --skip-api)
#   4. Smoke — run scripts/health-check.sh               (skip: --skip-smoke)

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# ── Configuration (env defaults; overridable via flags) ──────────────
TF_DIR="${IMAGEFLOW_TF_DIR:-$REPO_ROOT/terraform/environments/dev}"
API_HOST="${IMAGEFLOW_API_HOST:-127.0.0.1}"
API_PORT="${IMAGEFLOW_API_PORT:-8000}"
FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"

SKIP_TF=0
SKIP_API=0
SKIP_SMOKE=0

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy the ImageFlow stack to the local Floci cloud:
prerequisites → terraform apply → start API → smoke test.

Options:
  --tf-dir DIR       Terraform workspace dir (default: \$IMAGEFLOW_TF_DIR or ./terraform/environments/dev)
  --api-host HOST    API bind host         (default: \$IMAGEFLOW_API_HOST or 127.0.0.1)
  --api-port PORT    API bind port         (default: \$IMAGEFLOW_API_PORT or 8000)
  --floci-url URL    Floci endpoint URL    (default: \$FLOCI_ENDPOINT_URL or http://127.0.0.1:4566)
  --skip-terraform   Skip terraform init/apply
  --skip-api         Skip starting the API
  --skip-smoke       Skip the health-check smoke test
  -h, --help         Show this help and exit.

Exit codes:
  0   success
  1   failure
  2   usage error
EOF
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "missing prerequisite: $cmd (see docs/setup.md)"
        return 1
    fi
}

step_terraform() {
    require_cmd terraform || return 1
    if [ ! -d "$TF_DIR" ]; then
        error "terraform dir not found: $TF_DIR"
        return 1
    fi
    info "terraform: init + apply in $TF_DIR"
    terraform -chdir="$TF_DIR" init
    terraform -chdir="$TF_DIR" apply -auto-approve
}

step_api() {
    local uvicorn pid i real
    if [ -x "$REPO_ROOT/.venv/bin/uvicorn" ]; then
        uvicorn="$REPO_ROOT/.venv/bin/uvicorn"
    else
        require_cmd uvicorn || return 1
        uvicorn=uvicorn
    fi
    mkdir -p "$REPO_ROOT/data"
    # The backgrounded compound `cd && nohup uvicorn` makes $! the WRAPPER
    # subshell pid on macOS (nohup forks), so the pidfile can point at a dead
    # process — `chaos kill-api` would then fail with "not running". We
    # resolve the REAL listener pid below, once the app answers /health.
    (cd "$REPO_ROOT" && nohup "$uvicorn" app.main:app --host "$API_HOST" --port "$API_PORT" >> data/api.log 2>&1 & echo "$!" > data/api.pid)
    pid="$(cat "$REPO_ROOT/data/api.pid" 2>/dev/null || true)"
    info "api: starting uvicorn (pid ${pid:-?}) — log: $REPO_ROOT/data/api.log"

    for ((i = 1; i <= 10; i++)); do
        if curl -s --max-time 1 "http://$API_HOST:$API_PORT/health" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
            # Overwrite the pidfile with the process actually listening on the
            # port (lsof, fallback pgrep) so kill-api targets the real server.
            real="$(lsof -ti "tcp:$API_PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)"
            if [ -z "$real" ]; then
                # Fallback when lsof is unavailable: match our own uvicorn on
                # THIS port only (never an unrelated instance on another port).
                real="$(pgrep -f "uvicorn app.main:app.*--port $API_PORT" 2>/dev/null | head -1 || true)"
            fi
            if [ -n "$real" ]; then
                echo "$real" > "$REPO_ROOT/data/api.pid"
                info "api: healthy after ${i}s (pid $real)"
            else
                info "api: healthy after ${i}s (pid ${pid:-?})"
            fi
            return 0
        fi
        sleep 1
    done
    error "api: did not become healthy within 10s — see data/api.log"
    if [ -f "$REPO_ROOT/data/api.pid" ]; then
        kill "$(cat "$REPO_ROOT/data/api.pid")" 2>/dev/null || true
    fi
    return 1
}

step_smoke() {
    info "smoke: health-check API + Floci"
    "$REPO_ROOT/scripts/health-check.sh" --api-url "http://$API_HOST:$API_PORT" --floci-url "$FLOCI_URL"
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --tf-dir)
                [ "$#" -ge 2 ] || { error "--tf-dir requires a value"; usage >&2; return 2; }
                TF_DIR="$2"; shift 2 ;;
            --api-host)
                [ "$#" -ge 2 ] || { error "--api-host requires a value"; usage >&2; return 2; }
                API_HOST="$2"; shift 2 ;;
            --api-port)
                [ "$#" -ge 2 ] || { error "--api-port requires a value"; usage >&2; return 2; }
                case "$2" in
                    ''|0|*[!0-9]*) error "--api-port must be a positive integer"; usage >&2; return 2 ;;
                esac
                API_PORT="$2"; shift 2 ;;
            --floci-url)
                [ "$#" -ge 2 ] || { error "--floci-url requires a value"; usage >&2; return 2; }
                FLOCI_URL="$2"; shift 2 ;;
            --skip-terraform) SKIP_TF=1; shift ;;
            --skip-api)       SKIP_API=1; shift ;;
            --skip-smoke)     SKIP_SMOKE=1; shift ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    # 1. Prerequisites
    if [ "$SKIP_TF" -eq 0 ]; then
        if ! command -v terraform >/dev/null 2>&1; then
            error "missing prerequisite: terraform (see docs/setup.md)"
            return 1
        fi
    fi
    require_cmd curl || return 1
    if [ "$SKIP_SMOKE" -eq 0 ] && ! curl -s --max-time 2 -o /dev/null "$FLOCI_URL"; then
        error "Floci not reachable at $FLOCI_URL — run 'floci start' (docs/setup.md)"
        return 1
    fi

    # 2-4. Steps
    [ "$SKIP_TF" -eq 0 ]    && { step_terraform || return 1; }
    [ "$SKIP_API" -eq 0 ]   && { step_api || return 1; }
    [ "$SKIP_SMOKE" -eq 0 ] && { step_smoke || return 1; }

    info "deploy complete."
}

main "$@"
