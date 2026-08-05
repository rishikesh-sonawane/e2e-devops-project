#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-security — Phase 14 security demos on Floci (ADR-12).
#
# Usage: ./scripts/security.sh [kms|secrets|cognito|waf|iam|all]
#
# Demos (each self-contained; provisioned by the Terraform `security` module):
#   kms      KMS key: encrypt/decrypt round trip — prove ciphertext is opaque
#   secrets  Secrets Manager: write a generated token, read back masked
#   cognito  full auth flow: user → NEW_PASSWORD_REQUIRED → respond → JWT claims
#   waf      WAF v2 web ACL: show rate-limit + managed-rules statements
#   iam      least-privilege user: show the one-bucket scoped policy
#   all      run every demo
#
# Honest Floci note: Floci validates SigV4 signatures but does NOT enforce
# IAM authorization — the IAM demo shows policy DESIGN (real-AWS-correct);
# enforcement is a live control on a real account.
#
# Exit codes: 0 all demos OK · 1 a demo failed (aws/Floci unavailable) · 2 usage.
# Env overrides: FLOCI_ENDPOINT_URL · IMAGEFLOW_DEMO_TOKEN (else generated).

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

FLOCI_URL="${FLOCI_ENDPOINT_URL:-http://127.0.0.1:4566}"
KMS_ALIAS="alias/imageflow-app-key"
SECRET_NAME="imageflow/app-secret"
POOL_NAME="imageflow-users"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
step()  { printf '\n[STEP]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [kms|secrets|cognito|waf|iam|all]

Phase 14 security demos against Floci (requires the terraform security
module applied and 'aws' CLI on PATH).

Demos:
  kms      KMS encrypt/decrypt round trip (ciphertext opacity)
  secrets  Secrets Manager write/read with masked output
  cognito  Cognito user auth flow → JWT claims
  waf      WAF v2 web ACL rules
  iam      Least-privilege IAM user policy
  all      run every demo (default)

Env: FLOCI_ENDPOINT_URL, IMAGEFLOW_DEMO_TOKEN.
EOF
}

aws_cmd() {
    AWS_ENDPOINT_URL="$FLOCI_URL" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    AWS_DEFAULT_REGION=us-east-1 aws "$@"
}

# decode_jwt <token> — print the JSON payload of a JWT (cross-platform base64url).
decode_jwt() {
    python3 -c '
import base64, json, sys
payload = sys.argv[1].split(".")[1] + "=="
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2, sort_keys=True))
' "$1"
}

demo_kms() {
    step "KMS — encrypt/decrypt round trip"
    local plain plain_b64 cipher back_b64 back
    plain="imageflow-demo-plaintext"
    # The AWS CLI takes blob args base64-encoded and returns blob outputs
    # base64-encoded — encode/decode explicitly so the round trip is exact.
    plain_b64="$(printf '%s' "$plain" | base64)"
    cipher="$(aws_cmd kms encrypt --key-id "$KMS_ALIAS" --plaintext "$plain_b64" --query CiphertextBlob --output text)"
    back_b64="$(aws_cmd kms decrypt --key-id "$KMS_ALIAS" --ciphertext-blob "$cipher" --query Plaintext --output text)"
    back="$(printf '%s' "$back_b64" | python3 -c 'import base64,sys; print(base64.b64decode(sys.stdin.read().strip()).decode())')"
    info "ciphertext (opaque): ${cipher:0:24}... (${#cipher} chars)"
    if [ "$back" = "$plain" ]; then
        info "round trip OK: decrypted plaintext matches (never stored in clear elsewhere)"
    else
        error "round trip MISMATCH"
        return 1
    fi
}

demo_secrets() {
    step "Secrets Manager — write + masked read ($SECRET_NAME)"
    local token payload keys
    token="${IMAGEFLOW_DEMO_TOKEN:-$(openssl rand -hex 16)}"
    payload="{\"token\":\"$token\",\"environment\":\"dev\"}"
    aws_cmd secretsmanager put-secret-value --secret-id "$SECRET_NAME" --secret-string "$payload" >/dev/null
    keys="$(aws_cmd secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text \
        | python3 -c 'import json,sys; print(", ".join(sorted(json.load(sys.stdin).keys())))')"
    info "secret updated (new version); stored keys: $keys (values never echoed)"
}

demo_cognito() {
    step "Cognito — full auth flow → JWT claims"
    local pool_id client_id user temp_pass new_pass session tokens
    pool_id="$(aws_cmd cognito-idp list-user-pools --max-results 10 --query "UserPools[?Name=='$POOL_NAME'].Id" --output text)"
    [ -n "$pool_id" ] || { error "user pool '$POOL_NAME' not found — run terraform apply"; return 1; }
    client_id="$(aws_cmd cognito-idp list-user-pool-clients --user-pool-id "$pool_id" --query 'UserPoolClients[0].ClientId' --output text)"
    user="security-demo-$$"
    temp_pass="Temp#$(openssl rand -hex 6)"
    new_pass="NewPass#$(openssl rand -hex 6)"
    aws_cmd cognito-idp admin-create-user --user-pool-id "$pool_id" --username "$user" \
        --temporary-password "$temp_pass" --message-action SUPPRESS >/dev/null
    session="$(aws_cmd cognito-idp admin-initiate-auth --user-pool-id "$pool_id" --client-id "$client_id" \
        --auth-flow ADMIN_USER_PASSWORD_AUTH --auth-parameters "USERNAME=$user,PASSWORD=$temp_pass" \
        --query 'Session' --output text)"
    tokens="$(aws_cmd cognito-idp admin-respond-to-auth-challenge --user-pool-id "$pool_id" --client-id "$client_id" \
        --challenge-name NEW_PASSWORD_REQUIRED --session "$session" \
        --challenge-responses "USERNAME=$user,NEW_PASSWORD=$new_pass" \
        --query 'AuthenticationResult.IdToken' --output text)"
    info "authenticated; id_token claims:"
    decode_jwt "$tokens" | sed 's/^/  /'
    info "user $user deleted (throwaway)"
    aws_cmd cognito-idp admin-delete-user --user-pool-id "$pool_id" --username "$user" >/dev/null 2>&1 || true
}

demo_waf() {
    step "WAF v2 — web ACL rules"
    local acl_id
    acl_id="$(aws_cmd wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?Name=='imageflow-web-acl'].Id" --output text)"
    [ -n "$acl_id" ] || { error "web ACL not found — run terraform apply"; return 1; }
    aws_cmd wafv2 get-web-acl --scope REGIONAL --id "$acl_id" --name imageflow-web-acl \
        --query 'WebACL.Rules[].[Name,Action,Statement]' --output json \
        | python3 -c '
import json, sys
for name, action, stmt in json.load(sys.stdin):
    kind = "rate-bucket" if "RateBasedStatement" in stmt else "managed-rules" if "ManagedRuleGroupStatement" in stmt else "other"
    print(f"  rule: {name}  action: {list(action.keys())[0] if isinstance(action, dict) else action}  kind: {kind}")
'
}

demo_iam() {
    step "IAM — least-privilege user (design demo; Floci does NOT enforce)"
    local policy
    aws_cmd iam get-user --user-name imageflow-reader --query 'User.UserName' --output text >/dev/null \
        || { error "user imageflow-reader not found — run terraform apply"; return 1; }
    policy="$(aws_cmd iam get-user-policy --user-name imageflow-reader --policy-name read-uploads-only \
        --query 'PolicyDocument' --output json)"
    info "scoped policy (single bucket, read-only):"
    printf '%s\n' "$policy" | python3 -m json.tool | sed 's/^/  /'
    info "NOTE: policy design is real-AWS-correct; Floci validates signatures but not authorization (ADR-12)."
}

demo_all() {
    demo_kms
    demo_secrets
    demo_cognito
    demo_waf
    demo_iam
    step "ALL SECURITY DEMOS DONE"
}

main() {
    if ! command -v aws >/dev/null 2>&1; then
        error "missing prerequisite: aws CLI (see docs/setup.md)"
        return 1
    fi
    case "${1:-all}" in
        kms)     demo_kms ;;
        secrets) demo_secrets ;;
        cognito) demo_cognito ;;
        waf)     demo_waf ;;
        iam)     demo_iam ;;
        all)     demo_all ;;
        -h|--help) usage ;;
        *) error "unknown demo: $1"; usage >&2; return 2 ;;
    esac
}

main "$@"
