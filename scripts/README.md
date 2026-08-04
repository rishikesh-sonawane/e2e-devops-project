# scripts/ — Operational & Diagnostic Scripts (Phase 4)

These are the **Phase 4 (Bash & Automation)** deliverables. They are currently
**skeletons**: each script has a real, stable contract — shebang, `set -euo pipefail`,
`--help` flag, logging helpers, and documented exit codes — but the operational
logic lands in Phase 4. See `docs/roadmap.md` → Phase 4.

| Script | Purpose | Contract |
|---|---|---|
| `deploy.sh` | Deploy the stack (Terraform + API) to Floci | prerequisites → `terraform apply` → start API → smoke test |
| `health-check.sh` | Verify API `/health` + Floci `:4566` are alive | curl checks → report → exit 0/1 |
| `cleanup.sh` | Safely tear down local resources | confirm → `terraform destroy` → remove tmp/logs |
| `backup.sh` | Timestamped archive of project state | `tar` key dirs → `data/backups/` → verify |

## Usage

```bash
./scripts/deploy.sh --help        # contract + options (all four scripts support --help)
./scripts/deploy.sh               # runs the Phase 4 stub (prints contract, exit 0)
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
- **Never** touch the repository source tree during cleanup; **never** echo secrets.
- Real logic, tests, and `shellcheck` integration land in Phase 4.
