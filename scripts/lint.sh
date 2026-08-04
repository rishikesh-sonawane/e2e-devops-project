#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-script-lint — run shellcheck over all project shell scripts (Phase 4).
#
# Usage: ./scripts/lint.sh
# Requires: shellcheck  (install: brew install shellcheck)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

main() {
    local script failed=0

    if ! command -v shellcheck >/dev/null 2>&1; then
        error "shellcheck not installed — run: brew install shellcheck"
        return 1
    fi

    while IFS= read -r script; do
        shellcheck "$script" || failed=1
    done < <(find "$REPO_ROOT/scripts" -name '*.sh' -type f | sort)

    if [ "$failed" -eq 0 ]; then
        info "shellcheck: all scripts clean"
        return 0
    fi
    error "shellcheck: one or more scripts failed (see findings above)"
    return 1
}

main "$@"
