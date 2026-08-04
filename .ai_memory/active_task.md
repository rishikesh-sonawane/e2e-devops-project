# Active Task State

## Current Focus
**Full ImageFlow pipeline is LIVE end-to-end**: upload (`9e941dd`) → **process** (`2065ff1`, Lambda image-processor: Pillow thumbnail + metadata → PROCESSED + SNS image.processed, direct-mode via `scripts/process-pending.sh`) → retrieve (original_url + thumbnail_url presigned). 33/33 tests, ruff + shellcheck clean, CI green on GitHub. **Floci S3 event-notification config verified supported** — the primary `s3` trigger can be wired once the function is registered (Phase 10 infra). **Next: Terraform IaC (Phase 9/10)** — provision S3/DynamoDB/Lambda/SNS/IAM via terraform/, register the image-backed Lambda + S3 trigger, replace lazy in-app provisioning.

## Immediate Next Steps
1. [x] Scaffold the repository structure and a production-ready `.gitignore`.
2. [x] Write the initial `app/main.py` FastAPI application: `/health`, `/version`, `/metrics`, `/config` endpoints.
3. [x] Set up the Python virtual environment and pin `app/requirements.txt` (fastapi==0.141.1, uvicorn==0.52.1, boto3==1.43.63, prometheus-client==0.26.0, pydantic-settings==2.14.2, pytest==9.1.1, ruff==0.16.1, …).
4. [x] Test the FastAPI application locally (venv + uvicorn + smoke test; Floci not required for ops endpoints).
5. [x] Phase 2 — Source Control: branching strategy (feature/*), commit conventions, PR workflow, release tagging — documented in `docs/source-control.md`.
6. [x] Practice the Git workflow on real work: `feature/p4-bash-scripts` → 6 conventional commits → squash merge → branch deleted (PR steps activate once a remote exists).
7. [x] Phase 4 — Bash & Automation: all four scripts implemented + 26 tests + shellcheck (merged `434a333`).
8. [x] Build the ImageFlow pipeline endpoints — upload/get/list live against Floci (`9e941dd`).
9. [x] Push to origin + **CI is LIVE and GREEN** (`f7bd092` — fixed shellcheck version skew caught by first real run).
10. [x] Build the Lambda image-processor (Pillow thumbnail + metadata → PROCESSED + SNS event) — merged `2065ff1`, 33/33 tests, live-verified; Floci S3-notification wiring confirmed supported.
11. [ ] Install Terraform/OpenTofu; Phase 9/10 Terraform IaC — S3, DynamoDB, Lambda (image-backed + S3 trigger), SNS, IAM; replace lazy in-app provisioning.
12. [ ] Phase 11+ — Helm, EKS, monitoring, etc. (see docs/roadmap.md).


## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
