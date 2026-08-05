# Security Hardening — Phase 14

**Goal:** prove a production-grade security posture — least-privilege IAM
design, secrets management, encryption, identity, edge protection, and
supply-chain gates in CI — using AWS-native tooling, all locally on Floci for
$0. Design is real-AWS-correct; the honest Floci limits are called out.

> Replay: `terraform apply` (provisions all security resources) →
> `./scripts/security.sh all` (live demos) → `./scripts/security-audit.sh`
> (repo + IAM audit). CI enforces the gates on every push.

---

## 1. What Floci supports (probe-verified)

| Service | Status | Notes |
|---|---|---|
| Secrets Manager | ✅ create/put/get | Full JSON SecretString round trip |
| KMS | ✅ create-key/encrypt/decrypt | Real ciphertext blobs |
| Cognito | ✅ pools/clients/users/auth | **Faithful**: `NEW_PASSWORD_REQUIRED` challenge, real JWT claims |
| WAF v2 | ✅ web ACLs + rules | Rate + managed-rule statements stored |
| ACM | ✅ request-certificate | |
| CloudTrail | ✅ create-trail | |
| IAM/STS | ✅ users/policies/roles | **Signatures validated, authorization NOT enforced** (probe: a one-bucket user could still `ListBuckets`) |

## 2. IAM — least-privilege design

`terraform/modules/security` provisions the **`imageflow-reader`** demo user
with a single scoped policy (read-only on one bucket). The Lambda's IAM policy
was also tightened: `logs:CreateLogStream`/`PutLogEvents` are now scoped to
the function's log-group ARN instead of `*` (`terraform/modules/compute`).

```
imageflow-reader ──▶ s3:GetObject / s3:ListBucket   (imageflow-uploads ONLY)
```

**Honest Floci finding (ADR-12):** Floci validates SigV4 signatures but does
*not* enforce IAM authorization — the demo user can still list all buckets.
The policy *design* is real-AWS-correct and would be enforced on a real
account; locally it is a design/audit exercise, exactly like the CodeDeploy
simulation caveat in Phase 12.

`./scripts/security-audit.sh` runs the two-sided review:

```bash
./scripts/security-audit.sh
# 1. ripgrep secret scan — AWS keys, private keys, GitHub/Stripe/Slack
#    tokens, inline password/token assignments → FAILS on any finding
# 2. Floci IAM review — flags wildcard Resource/Action statements
```

The audit caught a real one during development: a literal fake AWS key in a
test fixture (now built at runtime) — proof the scan works.

## 3. Secrets Manager + KMS — the secrets flow

```
Secret created (scripts/security.sh) ──▶ Secrets Manager
                                            │
App startup: IMAGEFLOW_SECRET_NAME set ─────▶ get_secret_value → JSON
                                            │
resolve_aws_credentials() ──────────────────▶ AWS creds used by boto3 clients
                                            │
KMS (alias/imageflow-app-key) ── encrypt ──▶ opaque ciphertext (decrypt-only-with-key)
```

- `app/services/secrets.py` — `fetch_secret` / `put_secret` (upsert) /
  `kms_encrypt` / `kms_decrypt` / `resolve_aws_credentials`.
- When `IMAGEFLOW_SECRET_NAME=imageflow/aws-creds` is set, the API sources
  its AWS credentials from Secrets Manager instead of env — the rotating
  credentials pattern, verified live (clients built with secret-sourced
  creds).
- **Never fatal:** a secret-store outage degrades to the env fallback with a
  warning — the pipeline never dies because a secret is unreachable (ADR-12).
- The demo never echoes values: `security.sh secrets` shows only the stored
  *keys*; `security.sh kms` shows the opaque ciphertext and proves the
  decrypt round trip.

## 4. Cognito — identity & JWT auth

`security.sh cognito` runs the full flow live on Floci:

1. `admin-create-user` (temporary password)
2. `admin-initiate-auth` → **`NEW_PASSWORD_REQUIRED`** (faithful Cognito
   behavior)
3. `admin-respond-to-auth-challenge` → **real IdToken/AccessToken**
4. JWT payload decoded and displayed — `iss`, `sub`, `exp`, `aud`,
   `cognito:username` claims proven

The Terraform module provisions the pool + app client + a demo user whose
temporary password is a **generated** `random_password` (never a literal in
the repo — an audit would flag it).

## 5. WAF v2 — edge protection

`terraform/modules/security` provisions `imageflow-web-acl`:

| Rule | Priority | What it does |
|---|---|---|
| `rate-limit` | 1 | Blocks an IP after >100 requests/5 min (rate-based) |
| `aws-managed-common` | 2 | AWS-managed core OWASP rule set |

`security.sh waf` lists the live rules. On a real account you would
associate the ACL with the ALB / API Gateway stage; locally the ACL + rules
are stored and inspected (Floci has no ALB to attach to yet — Phase 10
expansion).

## 6. CI security gates (supply chain)

`.github/workflows/ci.yml` gained a `security` job (runs after quality+test)
and an image scan in `build`:

| Gate | Tool | Fails on |
|---|---|---|
| Dependency CVEs | `pip-audit` (both requirement files) | any known vuln |
| Secrets in git | `gitleaks` | secret-shaped strings in history/tree |
| Repo vulnerabilities | `trivy fs` | HIGH/CRITICAL, unfixed |
| Image vulnerabilities | `trivy image` (in build job) | HIGH/CRITICAL, unfixed |

Run locally with `act` (the security job runs under act too). These are the
same tools a real platform would gate on.

## 7. Threat model → control map (the interview answer)

| Threat | Control (Phase 14) |
|---|---|
| Stolen credentials / over-permissioned keys | least-privilege IAM design, secrets-backed creds |
| Secrets in source control | `security-audit.sh` + gitleaks in CI |
| Vulnerable dependencies / images | pip-audit + trivy in CI |
| Exposure of raw secrets | SecretStr masking (`/config`), demo never echoes values |
| Credential rotation | secrets-backed `resolve_aws_credentials()` |
| Brute force / OWASP attacks | WAF rate-limit + managed rules |
| Unauthorized access | Cognito auth flow (JWT) |

## 8. Demo runbook (5 minutes)

```bash
floci start && eval $(floci env)
terraform -chdir terraform/environments/dev apply    # KMS, secret, pool, ACL, user
./scripts/security.sh all                            # 5 live demos
./scripts/security-audit.sh                          # secret scan + IAM review
# secrets-backed app creds:
IMAGEFLOW_SECRET_NAME=imageflow/aws-creds uvicorn app.main:app --port 8000
```

## 9. What Phase 14 deliberately leaves local

- **IAM enforcement, WAF attachment, ACM issuance completion, CloudTrail
  delivery** are real-account controls — Floci stores the configuration but
  cannot execute the enforcement/network planes (documented honestly).
- Production secrets would come from an external secrets manager or OIDC;
  locally everything is the dummy `test`/`test` pair or demo values.
