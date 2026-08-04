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
- **Toolchain:** Floci CLI 0.2.0 (`~/.local/bin`), AWS CLI 2.36.15, Docker 29.5.2, shellcheck, act, Pillow 12.3.0, Terraform 1.15.8 (hashicorp tap), **Helm 4.2.3**, kubectl 1.34.1. OpenTofu NOT used (Terraform only). **Floci EKS cluster `imageflow-test` ACTIVE** (real k3s v1.34.1+k3s1, endpoint :6500).
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
- [x] Pipeline processing — **Lambda image-processor LIVE** (`2065ff1`): Pillow thumbnail + metadata → PROCESSED + SNS image.processed; trigger paths s3 (event) / direct (process-pending.sh); FAILED dead-letter; 33/33 tests
- [x] **Phase 9/10 IaC LIVE** (`9b745dc`): Terraform modules + environments/dev provision S3, DynamoDB, SNS, IAM, ECR, image-backed Lambda + S3 trigger against Floci; S3 remote state + DDB locking on Floci; plan idempotent; **S3→Lambda auto-delivery verified (upload → PROCESSED in ~5s)**; replaces lazy in-app provisioning
- [x] **Phase 11 ORCHESTRATION LIVE** (`51661a5`): helm/imageflow chart (Deployment, Service, ConfigMap, Secret, HPA, optional Ingress) deployed to **Floci EKS = real k3s** (node v1.34.1+k3s1). API image in Floci ECR via `scripts/push-api.sh`. Verified: pod Running, /health ok, real upload via clustered API → S3 → **live Lambda auto-processed it** (PROCESSED + thumbnail), HPA reports cpu 14%/70%, `helm upgrade --install` idempotent. **Known Floci quirk:** k3s node needs `/etc/hosts` entry for `floci-ecr-registry` (default docker bridge has no embedded DNS) or ImagePullBackOff — documented in helm README
- [ ] Local Docker Containerization
- [ ] Local Kubernetes Cluster & Helm Chart Setup (Floci EKS)
- [ ] Infrastructure as Code (Terraform for S3/DynamoDB/Lambda/SNS)
- [ ] GitHub Actions Pipeline (CI/CD)
- [x] **Phase 7/8 INNER-LOOP CI/CD LIVE** (`69fe882`): CodePipeline `imageflow-pipeline` (S3 source → CodeBuild → CodeDeploy) end-to-end **Succeeded**. CodeBuild runs the real buildspec — ruff + pytest quality gates, then **Kaniko daemonless** image build + push to Floci ECR (`host.docker.internal:5100/imageflow-api:latest`, verified in registry). CodeDeploy targets on-premises DG `imageflow-onprem` (auto-rollback on failure) — Floci resolves targets via on-premises registration + tags (EC2-tag DGs fail `NoInstancesReachable`); deployment lifecycle is **simulated** by Floci (hooks real-AWS-correct, not executed locally). GitHub Actions `deploy.yml` (gate→test→push+trigger pipeline, uploads source.zip first) + `release.yml` (tag→build+push→terraform validate→GH release) — act dry-runs list all jobs. `scripts/setup-inner-loop.sh` provisions everything idempotently. **ADR-10 = deviation log** (Kaniko: Floci CodeBuild has no docker daemon — proven by probe; toolchain cached in S3; tar:// context required; cwd deleted mid-build → no post_build phase).
- [ ] Monitoring & Observability
- [ ] Security Hardening (IAM, Secrets Manager, WAF)
- [ ] Troubleshooting Lab & Interview Prep

## Architectural Decisions
See `.ai_memory/architectural_decisions.md` (ADR-10 = Kaniko deviation log + Floci CodeDeploy findings).
