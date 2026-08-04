# scripts/ — Operational & Diagnostic Scripts (Phase 4)

These are the **Phase 4 (Bash & Automation)** deliverables. Each script has a
real, stable contract — shebang, `set -euo pipefail`, `--help` flag, logging
helpers, and documented exit codes. `health-check.sh` is **fully implemented**;
`deploy.sh`, `cleanup.sh`, and `backup.sh` are still skeletons whose operational
logic lands as Phase 4 progresses. See `docs/roadmap.md` → Phase 4.

| Script | Purpose | Contract |
|---|---|---|
| `deploy.sh` | Deploy the stack (Terraform + API) to Floci | prerequisites → `terraform apply` → start API → smoke test |
| `health-check.sh` | ✅ implemented — verify API `/health` + Floci cloud are alive | GET `/health` (must say `status=ok`) + Floci HTTP reachability → per-service report → exit 0/1 |
| `cleanup.sh` | Safely tear down local resources | confirm → `terraform destroy` → remove tmp/logs |
| `backup.sh` | Timestamped archive of project state | `tar` key dirs → `data/backups/` → verify |

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
- Remaining Phase 4 work: real logic for `deploy.sh`/`cleanup.sh`/`backup.sh`, and
  `shellcheck` integration (install via `brew install shellcheck`).
