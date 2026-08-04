#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-backup — snapshot local project state into a timestamped archive.
#
# Usage: ./scripts/backup.sh [--help]
#
# This is a Phase 4 (Bash & Automation) skeleton. It defines the script's
# contract — flags, exit codes, log output, and the intended backup — and
# will be fleshed out with real logic in Phase 4. See docs/roadmap.md.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--help]

Create a timestamped archive of key project state (docs, scripts, .ai_memory)
under data/backups/. Source of truth remains Git; this is a convenience snapshot.

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   success
  1   failure
  2   usage error
EOF
}

main() {
    if [ "$#" -gt 1 ]; then
        error "too many arguments"; usage >&2; return 2
    fi

    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        "")        : ;;                       # no args — run the stub
        *)         error "unknown option: $1"; usage >&2; return 2 ;;
    esac

    info "$SCRIPT_NAME: Phase 4 skeleton — implementation lands in Phase 4."
    info "Contract: tar key dirs → data/backups/imageflow-<timestamp>.tar.gz → verify archive."
    # TODO(Phase 4): real backup logic.
    return 0
}

main "$@"
