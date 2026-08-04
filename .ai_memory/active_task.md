# Active Task State

## Current Focus
**CI-ready foundation COMPLETE** (`4e09dbe`) — multi-stage non-root Dockerfile (build + run smoke verified), config tests (pytest 10/10), and `.github/workflows/ci.yml` (ruff → pytest → shellcheck → docker build) validated locally with act; goes live when a GitHub remote is created. Phase 4 complete (26 script tests), Phase 2 complete (GitHub Flow practiced). **Next: build the ImageFlow pipeline endpoints (POST /api/v1/images → S3 + DynamoDB via Floci)** — REQUIRES installing Floci CLI + AWS CLI and starting the cloud (`floci start`).

## Immediate Next Steps
1. [x] Scaffold the repository structure and a production-ready `.gitignore`.
2. [x] Write the initial `app/main.py` FastAPI application: `/health`, `/version`, `/metrics`, `/config` endpoints.
3. [x] Set up the Python virtual environment and pin `app/requirements.txt` (fastapi==0.141.1, uvicorn==0.52.1, boto3==1.43.63, prometheus-client==0.26.0, pydantic-settings==2.14.2, pytest==9.1.1, ruff==0.16.1, …).
4. [x] Test the FastAPI application locally (venv + uvicorn + smoke test; Floci not required for ops endpoints).
5. [x] Phase 2 — Source Control: branching strategy (feature/*), commit conventions, PR workflow, release tagging — documented in `docs/source-control.md`.
6. [x] Practice the Git workflow on real work: `feature/p4-bash-scripts` → 6 conventional commits → squash merge → branch deleted (PR steps activate once a remote exists).
7. [x] Phase 4 — Bash & Automation: all four scripts implemented + 26 tests + shellcheck (merged `434a333`).
8. [ ] Build the ImageFlow pipeline endpoints (POST /api/v1/images upload → S3 + DynamoDB via Floci) — the app's core.
9. [ ] Install remaining toolchain: Floci CLI, AWS CLI v2, Terraform (and Helm for Phase 11) — audit showed these MISSING; Docker daemon now running.
10. [ ] Create the GitHub remote (unblocks real CI/PRs per docs/source-control.md).
11. [ ] Phase 9+ — Terraform, Helm, EKS, monitoring, etc. (see docs/roadmap.md).


## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
