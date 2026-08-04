#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-cleanup — tear down local ImageFlow resources safely.
#
# Usage: ./scripts/cleanup.sh [--tf-dir DIR] [--yes] [--help]
#
# Phase 4 behavior:
#   1. Confirm intent (skipped with --yes)
#   2. terraform destroy in terraform/ (if a tf binary and the dir exist)
#   3. Remove runtime artifacts in data/ (api.log, api.pid — data/ is gitignored)
#
# Never touches the repository source tree and never removes unknown files.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

TF_DIR="${IMAGEFLOW_TF_DIR:-$REPO_ROOT/terraform/environments/dev}"
ASSUME_YES=0

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely tear down local ImageFlow resources.

Options:
  --tf-dir DIR   Terraform workspace dir (default: \$IMAGEFLOW_TF_DIR or ./terraform/environments/dev)
  -y, --yes      Skip the confirmation prompt
  -h, --help     Show this help and exit.

Exit codes:
  0   success
  1   failure
  2   usage error
EOF
}

main() {
    local answer

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --tf-dir)
                [ "$#" -ge 2 ] || { error "--tf-dir requires a value"; usage >&2; return 2; }
                TF_DIR="$2"; shift 2 ;;
            -y|--yes) ASSUME_YES=1; shift ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    # 1. Confirm
    if [ "$ASSUME_YES" -eq 0 ]; then
        printf 'Tear down local ImageFlow resources? [y/N] ' >&2
        read -r answer || true
        case "$answer" in
            y|Y|yes) : ;;
            *) info "aborted."; return 0 ;;
        esac
    fi

    # 2. Terraform destroy (only when the workspace exists AND terraform is present)
    if [ -d "$TF_DIR" ] && command -v terraform >/dev/null 2>&1; then
        info "terraform: destroy in $TF_DIR"
        terraform -chdir="$TF_DIR" destroy -auto-approve || { error "terraform destroy failed"; return 1; }
    else
        info "skipping terraform destroy (no $TF_DIR or no terraform binary)"
    fi

    # 3. Runtime artifacts (known filenames only — never rm -rf, never source tree)
    if [ -d "$REPO_ROOT/data" ]; then
        info "removing runtime artifacts in $REPO_ROOT/data"
        rm -f "$REPO_ROOT/data/api.log" "$REPO_ROOT/data/api.pid"
        rmdir "$REPO_ROOT/data" 2>/dev/null || true
    fi

    info "cleanup complete."
}

main "$@"
