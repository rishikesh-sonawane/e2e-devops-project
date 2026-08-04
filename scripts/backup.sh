#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-backup — snapshot key project state into a timestamped archive.
#
# Usage: ./scripts/backup.sh [--out DIR] [--help]
#
# Phase 4 behavior:
#   Archive docs/, scripts/, .ai_memory/, app source, and root docs into
#   data/backups/imageflow-<timestamp>.tar.gz, then verify the archive.
#   Git remains the source of truth — this is a convenience snapshot.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

OUT_DIR="${IMAGEFLOW_BACKUP_DIR:-$REPO_ROOT/data/backups}"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Create a timestamped archive of key project state (docs, scripts, .ai_memory,
app source, root docs) and verify it.

Options:
  --out DIR    Backup directory (default: \$IMAGEFLOW_BACKUP_DIR or data/backups)
  -h, --help   Show this help and exit.

Exit codes:
  0   success
  1   failure
  2   usage error
EOF
}

main() {
    local stamp archive size

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --out)
                [ "$#" -ge 2 ] || { error "--out requires a value"; usage >&2; return 2; }
                OUT_DIR="$2"; shift 2 ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    stamp="$(date +%Y%m%d-%H%M%S)-$$"
    archive="$OUT_DIR/imageflow-$stamp.tar.gz"
    mkdir -p "$OUT_DIR"

    info "archiving key state → $archive"
    tar -czf "$archive" -C "$REPO_ROOT" \
        docs scripts .ai_memory app \
        pyproject.toml README.md AGENTS.md

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        error "archive verification failed: $archive"
        return 1
    fi

    size="$(du -h "$archive" | cut -f1)"
    info "backup complete: $archive ($size)"
}

main "$@"
