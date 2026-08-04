# Active Task State

## Current Focus
**Full ImageFlow pipeline is LIVE end-to-end AND Terraform-provisioned** (`9b745dc`): upload → S3 → **S3 event notification fires the image-backed Lambda automatically** (PROCESSED in ~5s, verified) → thumbnail + DynamoDB + SNS. Terraform modules + environments/dev with Floci S3 remote state + DynamoDB locking; plan idempotent; 33/33 tests stable; CI green (incl. terraform validate). **Terraform only** (no OpenTofu) per user directive. Lambda env gotcha documented: never set AWS_ENDPOINT_URL (Floci injects its own; localhost inside container ≠ host).

## Immediate Next Steps

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
11. [x] Terraform 1.15.8 installed (hashicorp tap); **Phase 9/10 IaC live** — S3, DynamoDB, SNS, IAM, ECR, image-backed Lambda + S3 trigger; remote state on Floci; auto-delivery verified.
12. [ ] Phase 11 — Helm chart (helm/imageflow) + Floci EKS (k3s) deployment of the API.
13. [ ] Phase 7/8 finish — push API image to ECR, CodePipeline/CodeBuild inner loop, release workflow (deploy.yml/release.yml).
14. [ ] Monitoring (CloudWatch/OpenSearch), security (IAM/KMS/Secrets), troubleshooting lab (see docs/roadmap.md).


## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
