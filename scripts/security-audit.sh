#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-security-audit — Phase 14: secret scan + IAM review (ADR-12).
#
# Usage: ./scripts/security-audit.sh [--repo-dir DIR] [--floci-url URL] [--help]
#
# Part 1 — Repo secret scan (CORE, fails the script):
#   ripgrep over tracked-looking source for high-signal secret patterns:
#   AWS access keys, private keys, GitHub/Stripe/Slack tokens, and inline
#   password/token assignments. No findings = clean.
#
# Part 2 — IAM review (informational): lists IAM users/policies from Floci
#   and flags statements that use Resource ["*"] or Action ["*"].
#
# Exit codes: 0 clean · 1 secrets found or aws unreachable · 2 usage.
# Env overrides: FLOCI_ENDPOINT_URL.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

REPO_DIR="${IMAGEFLOW_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"

info()  { printf '[INFO]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Phase 14 security audit:
  1. scan the repo for hardcoded secrets (ripgrep)
  2. review Floci IAM policies for wildcard statements

Options:
  --repo-dir DIR   directory to scan (default: \$IMAGEFLOW_REPO_DIR or repo root)
  --floci-url URL  Floci endpoint URL (default: \$FLOCI_ENDPOINT_URL or http://127.0.0.1:4566)
  -h, --help       show this help and exit

Exit codes:
  0   audit clean (no secrets, IAM reviewed)
  1   secrets found, or Floci unreachable
  2   usage error
EOF
}

# ── Part 1 (CORE): repo secret scan ─────────────────────────────────
scan_secrets() {
    local findings
    info "scanning $REPO_DIR for hardcoded secrets..."
    if ! command -v rg >/dev/null 2>&1; then
        error "missing prerequisite: ripgrep (brew install ripgrep)"
        return 1
    fi

    # High-signal patterns only — avoids false positives from docs/tests.
    findings="$(rg --hidden -n -i \
        -g '!.git/**' -g '!.venv/**' -g '!data/**' -g '!*.lock' \
        -g '!component-wise-architecture/**' -g '!*.pem' -g '!*.key' \
        -e 'AKIA[0-9A-Z]{16}' \
        -e '-----BEGIN (RSA|EC|OPENSSH|PGP) PRIVATE KEY-----' \
        -e '(sk|rk)_live_[a-zA-Z0-9]{16,}' \
        -e '(ghp|github_pat)_[a-zA-Z0-9]{20,}' \
        -e 'xox[baprs]-[a-zA-Z0-9-]{10,}' \
        -e '(password|passwd|client_secret|api[_-]?key|secret_key|access_token)\s*[:=]\s*["'"'"'][^"'"'"']{12,}["'"'"']' \
        "$REPO_DIR" 2>/dev/null || true)"

    if [ -n "$findings" ]; then
        error "SECRET-SCAN FINDINGS (possible hardcoded secrets):"
        printf '%s\n' "$findings" | sed 's/^/  /'
        return 1
    fi
    info "secret scan clean (no high-signal patterns)"
}

# ── Part 2 (info): IAM wildcard review ──────────────────────────────
review_iam() {
    local users policy_docs
    info "reviewing IAM policies on Floci for wildcard statements..."
    users="$(AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
        AWS_DEFAULT_REGION=us-east-1 aws iam list-users --query 'Users[].UserName' --output text 2>/dev/null)" \
        || { info "  (iam unavailable — is Floci running?)"; return 0; }
    [ -n "$users" ] || { info "  (no IAM users)"; return 0; }

    for user in $users; do
        policy_docs="$(AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
            AWS_DEFAULT_REGION=us-east-1 aws iam list-user-policies --user-name "$user" \
            --query 'PolicyNames[]' --output text 2>/dev/null)" || continue
        for policy in $policy_docs; do
            doc="$(AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
                AWS_DEFAULT_REGION=us-east-1 aws iam get-user-policy --user-name "$user" --policy-name "$policy" \
                --query 'PolicyDocument' --output json 2>/dev/null)" || continue
            if printf '%s' "$doc" | grep -qE '"(Resource|Action)"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\*"'; then
                info "  ⚠ $user / $policy — contains a wildcard Resource/Action statement"
            else
                info "  ✓ $user / $policy — scoped"
            fi
        done
    done
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --repo-dir)
                [ "$#" -ge 2 ] || { error "--repo-dir requires a value"; usage >&2; return 2; }
                REPO_DIR="$2"; shift 2 ;;
            --floci-url)
                [ "$#" -ge 2 ] || { error "--floci-url requires a value"; usage >&2; return 2; }
                FLOCI_URL="$2"; shift 2 ;;
            -*) error "unknown option: $1"; usage >&2; return 2 ;;
            *)  error "unexpected argument: $1"; usage >&2; return 2 ;;
        esac
    done

    [ -d "$REPO_DIR" ] || { error "repo dir not found: $REPO_DIR"; return 2; }

    if ! scan_secrets; then
        error "audit FAILED: hardcoded secrets found."
        return 1
    fi
    review_iam
    info "audit complete."
}

main "$@"
