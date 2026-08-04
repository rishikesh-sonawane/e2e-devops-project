# Active Task State

## Current Focus
Phase 1 (Application Foundation) in progress — repository scaffolded (canonical structure + production `.gitignore` committed). Next: build the ImageFlow API (`app/main.py`) with the Phase 1 endpoints.

## Immediate Next Steps
1. [x] Scaffold the repository structure (app/, lambda/image-processor/, terraform/, helm/imageflow/, scripts/, .github/workflows/, tests/) and a production-ready `.gitignore`.
2. [ ] Write the initial `app/main.py` FastAPI application: `/health`, `/version`, `/metrics`, `/config` endpoints.
3. [ ] Set up the Python virtual environment and pin `app/requirements.txt` (fastapi, uvicorn, boto3, python-multipart, prometheus-client, pytest); pin `lambda/image-processor/requirements.txt` (pillow) separately per ADR-06.
4. [ ] Test the FastAPI application locally against Floci (venv + uvicorn + smoke test).
5. [ ] Move to Phase 7+ topics: Dockerfile, then CI/CD, Terraform, etc. (see docs/roadmap.md).

## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
