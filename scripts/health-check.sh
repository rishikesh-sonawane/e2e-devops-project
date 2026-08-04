#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-health-check — verify ImageFlow services are alive (API + Floci).
#
# Usage: ./scripts/health-check.sh [--help]
#
# This is a Phase 4 (Bash & Automation) skeleton. It defines the script's
# contract — flags, exit codes, log output, and the intended checks — and
# will be fleshed out with real logic in Phase 4. See docs/roadmap.md.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--help]

Check that the ImageFlow API (/health) and the local Floci cloud (:4566)
are reachable. Exits non-zero if any check fails.

Options:
  -h, --help    Show this help and exit.

Exit codes:
  0   all checks healthy
  1   one or more checks failed
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
    info "Contract: curl API /health → check Floci :4566 → report + exit code."
    # TODO(Phase 4): real health checks.
    return 0
}

main "$@"
