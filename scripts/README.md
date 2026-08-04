# scripts/ — Operational & Diagnostic Scripts (Phase 4)

These are the **Phase 4 (Bash & Automation)** deliverables — **all fully
implemented**. Each script has a real, stable contract: shebang, `set -euo
pipefail`, `--help` flag, logging helpers, documented exit codes (0 success ·
1 failure · 2 usage error), and a behavior test suite in `scripts/tests/`.
See `docs/roadmap.md` → Phase 4.

| Script | Purpose | Contract |
|---|---|---|
| `deploy.sh` | Deploy the stack (Terraform + API) to Floci | prerequisites → `terraform apply` → start API → smoke test |
| `health-check.sh` | Verify API `/health` + Floci cloud are alive | GET `/health` (must say `status=ok`) + Floci HTTP reachability → per-service report → exit 0/1 |
| `cleanup.sh` | Safely tear down local resources | confirm (or `--yes`) → `terraform destroy` → remove `data/` artifacts |
| `backup.sh` | Timestamped archive of project state | `tar` key dirs → `data/backups/` → verify → report size |
| `lint.sh` | Run shellcheck over all scripts | requires shellcheck; exit 1 on any finding |

## Usage

```bash
./scripts/deploy.sh --help        # contract + options (all four scripts support --help)
./scripts/deploy.sh               # runs the Phase 4 stub (prints contract, exit 0)
```

## health-check.sh (implemented)

```bash
./scripts/health-check.sh                                     # defaults: API :8000, Floci :4566, timeout 3s
./scripts/health-check.sh --api-url http://127.0.0.1:8022 \
                          --floci-url http://127.0.0.1:4567 \
                          --timeout 2
```

**Flags:** `--api-url URL` · `--floci-url URL` · `--timeout SEC` · `-h|--help`
**Env overrides:** `IMAGEFLOW_API_URL` · `FLOCI_ENDPOINT_URL` · `IMAGEFLOW_HEALTH_TIMEOUT` (flags win)

**Behavior:** `GET <api-url>/health` must return HTTP 200 **and** a body containing
`"status":"ok"` (a 200 without the liveness body counts as DEGRADED). Floci is
healthy when it answers over HTTP. One status line per service, then either
`All services healthy.` (exit 0) or `N service(s) failed — health check FAILED.`
(exit 1). Usage errors exit 2.

**Tests:** `./scripts/tests/test_health-check.sh` — exit-code behavior tests plus
an all-up case against a real FastAPI server (repo venv) and a throwaway HTTP
server standing in for Floci.

## deploy.sh (implemented)

```bash
./scripts/deploy.sh                                        # full pipeline (needs Floci + terraform)
./scripts/deploy.sh --skip-terraform                       # infra already applied
./scripts/deploy.sh --skip-api --skip-smoke                # infra only
```

**Flags:** `--tf-dir` · `--api-host` · `--api-port` · `--floci-url` ·
`--skip-terraform` · `--skip-api` · `--skip-smoke` · `-h|--help`
**Env overrides:** `IMAGEFLOW_TF_DIR` · `IMAGEFLOW_API_HOST` · `IMAGEFLOW_API_PORT` · `FLOCI_ENDPOINT_URL`

**Pipeline:** (1) prereqs — terraform, curl, reachable Floci ·
(2) `terraform init + apply -auto-approve` · (3) start uvicorn from the repo
venv, wait for `/health` (10s), write `data/api.pid` + `data/api.log` ·
(4) smoke test via `health-check.sh`.

## cleanup.sh (implemented)

```bash
./scripts/cleanup.sh                  # asks for confirmation
./scripts/cleanup.sh --yes            # no prompt (scripts/CI)
```

**Flags:** `--tf-dir` · `-y|--yes` · `-h|--help`
**Env overrides:** `IMAGEFLOW_TF_DIR`

**Behavior:** confirm → `terraform destroy -auto-approve` (only if the workspace
exists and a tf binary is present) → remove the known runtime artifacts
(`data/api.log`, `data/api.pid`). Never `rm -rf`, never touches the source tree.

## backup.sh (implemented)

```bash
./scripts/backup.sh                                    # → data/backups/imageflow-<ts>.tar.gz
./scripts/backup.sh --out /tmp/backups
```

**Flags:** `--out DIR` · `-h|--help` · **Env override:** `IMAGEFLOW_BACKUP_DIR`

**Behavior:** archives `docs/ scripts/ .ai_memory/` + app source + root docs,
verifies the archive (`tar -tzf`), and reports the path and size.

## Linting (shellcheck)

```bash
brew install shellcheck
./scripts/lint.sh                      # exit 1 on any finding
```

## Exit codes (shared convention)

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failure |
| 2 | Usage error (unknown option) |

## Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail` (strict mode) in every script.
- Log lines to stdout (`[INFO]`), errors to stderr (`[ERROR]`).
- Exit codes: `0` success · `1` failure · `2` usage error.
- **Never** touch the repository source tree during cleanup; **never** echo secrets.
- Tests live in `scripts/tests/` and are run like `./scripts/tests/test_health-check.sh`.
- Lint every script with `./scripts/lint.sh` (shellcheck).
