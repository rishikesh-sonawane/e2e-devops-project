# Active Task State

## Current Focus
**Phase 2 (Source Control) in progress** — Git workflow documented in `docs/source-control.md` (GitHub Flow: sacred `main` + short-lived `feature/*`; Conventional Commits; PRs with passing checks, squash-merged; semver release tags). The workflow is now being **practiced on real work** — all future changes land on `feature/*` branches → PR → squash merge (the PR steps activate once a GitHub remote exists, Phase 8; until then, local feature-branch discipline). Phase 1 (API foundation) remains verified: pytest 5/5, ruff clean, live smoke test passed.

## Immediate Next Steps
1. [x] Scaffold the repository structure and a production-ready `.gitignore`.
2. [x] Write the initial `app/main.py` FastAPI application: `/health`, `/version`, `/metrics`, `/config` endpoints.
3. [x] Set up the Python virtual environment and pin `app/requirements.txt` (fastapi==0.141.1, uvicorn==0.52.1, boto3==1.43.63, prometheus-client==0.26.0, pydantic-settings==2.14.2, pytest==9.1.1, ruff==0.16.1, …).
4. [x] Test the FastAPI application locally (venv + uvicorn + smoke test; Floci not required for ops endpoints).
5. [x] Phase 2 — Source Control: branching strategy (feature/*), commit conventions, PR workflow, release tagging — documented in `docs/source-control.md`.
6. [ ] Practice the Git workflow on real work: every future change lands on a `feature/*` branch, merged via PR (squash) once a remote exists — until then, local feature-branch discipline.
7. [ ] Phase 7+ — Dockerfile, CI/CD, Terraform, Helm, etc. (see docs/roadmap.md).

## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
