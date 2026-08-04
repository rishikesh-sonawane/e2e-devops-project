#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-deploy — deploy the ImageFlow stack to the local Floci cloud.
#
# Usage: ./scripts/deploy.sh [--help]
#
# This is a Phase 4 (Bash & Automation) skeleton. It defines the script's
# contract — flags, exit codes, log output, and the intended pipeline — and
# will be fleshed out with real logic in Phase 4. See docs/roadmap.md.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--help]

Deploy the ImageFlow stack (Terraform + API) to the local Floci cloud.

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
    info "Contract: prerequisites (floci/terraform/aws/venv) → terraform apply → start API → smoke test."
    # TODO(Phase 4): real deploy logic.
    return 0
}

main "$@"
