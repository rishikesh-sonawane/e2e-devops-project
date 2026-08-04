# Current System State

## Tech Stack
- **Backend API:** Python 3.12 (FastAPI) + boto3
- **Cloud Integrations:** AWS S3, AWS DynamoDB, AWS Lambda, AWS SNS (via Floci, local emulator)
- **Event-Driven Pipeline:** ImageFlow — upload → S3 → Lambda (Pillow thumbnail + metadata) → DynamoDB + SNS
- **Infrastructure:** Terraform (HCL) with Floci S3 remote state + DynamoDB locking
- **Containerization:** Multi-stage Docker (non-root `python:3.12-slim`), Floci ECR
- **Orchestration:** Kubernetes (Floci EKS — real k3s) + Helm; Floci ECS
- **CI/CD:** Dual-loop — GitHub Actions (outer) + Floci CodePipeline/CodeBuild/CodeDeploy (inner)
- **Cost:** $0. Everything runs locally on Floci (localhost:4566, creds test/test, region us-east-1).
- **AI Assistants:** Freebuff (primary, continuous) · OpenCode Zen `big-pickle` (occasional, between sessions) — see ADR-08.
- **Toolchain:** Floci CLI 0.2.0 (installed to `~/.local/bin` — no-sudo), AWS CLI 2.36.15, Docker 29.5.2 running, shellcheck, act. Still missing: Terraform/OpenTofu, Helm.
- **Remote:** `origin` = github.com/rishikesh-sonawane/e2e-devops-project (public). **CI is LIVE and GREEN** — first run `a8e9603` failed (shellcheck version skew: apt 0.9.0 vs brew 0.11.0), fixed and verified green on `f7bd092` (shellcheck pinned to v0.11.0). Every push to main now runs ruff → shellcheck → pytest → docker build.

## Component Status
- [x] Phase 0 — Planning & Architecture (docs aligned to a single vision: README, docs/, AGENTS.md, .ai_memory/)
- [x] AI collaboration setup documented (Freebuff primary + OpenCode Zen occasional, ADR-08)
- [x] Directory Skeleton + .gitignore Created
- [x] Phase 1 — Application Foundation (FastAPI: /health /version /metrics /config + config module + unit tests, pytest 10/10)
- [x] Phase 2 — Source Control (GitHub Flow, Conventional Commits, PR + squash merge, semver tags — `docs/source-control.md`)
- [x] Phase 2 practiced end-to-end: `feature/p4-bash-scripts` → 6 conventional commits → squash merge → branch deleted
- [x] Phase 4 — Bash & Automation **COMPLETE** (all four scripts implemented + tested, shellcheck clean): health-check.sh (API/Floci checks), deploy.sh (terraform apply → API start → smoke), cleanup.sh (confirmed destroy + artifact removal), backup.sh (verified timestamped tar) — 26 behavior tests pass, `scripts/lint.sh` shellcheck-clean
- [x] Phase 7 kickoff — Dockerfile (multi-stage, non-root, HEALTHCHECK) + .dockerignore; build + container smoke verified
- [x] Phase 8 kickoff — .github/workflows/ci.yml (ruff → pytest → shellcheck → docker build) written + validated locally (act)
- [x] **CI LIVE & GREEN on GitHub** (first real run caught shellcheck version skew — fixed + pinned, verified passing on `f7bd092`)
- [x] ImageFlow pipeline — **upload/get/list endpoints LIVE** (`POST/GET /api/v1/images` → S3 + DynamoDB PENDING, verified against real Floci, 18 tests)
- [ ] Pipeline processing — Lambda image-processor (Pillow thumbnail + metadata → PROCESSED + SNS image.processed)
- [ ] Terraform IaC (Phase 9) — replace lazy in-app provisioning
- [ ] Local Docker Containerization
- [ ] Local Kubernetes Cluster & Helm Chart Setup (Floci EKS)
- [ ] Infrastructure as Code (Terraform for S3/DynamoDB/Lambda/SNS)
- [ ] GitHub Actions Pipeline (CI/CD)
- [ ] Floci CodePipeline Inner Loop
- [ ] Monitoring & Observability
- [ ] Security Hardening (IAM, Secrets Manager, WAF)
- [ ] Troubleshooting Lab & Interview Prep

## Architectural Decisions
See `.ai_memory/architectural_decisions.md`.
