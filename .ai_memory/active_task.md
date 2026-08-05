# Active Task State

## Current Focus
**Phase 13 — Monitoring & Observability COMPLETE** (`feature/p13-monitoring`, commits pending push): three observability planes live on Floci — Prometheus `/metrics` pipeline counters/histogram, CloudWatch custom metrics (ImageFlow namespace: API Uploads/UploadErrors + Lambda ProcessedCount/FailedCount), optional CloudWatch Logs handler (`/imageflow/api`, background flusher), and Terraform alarm + EventBridge→SNS alerting (live-applied). `scripts/observability.sh` report + `docs/monitoring.md` write-up (SLI/SLO + runbook). Floci findings logged in ADR-11 (alarm actions not persisted; logs = separate boto3 service; background flusher required). 42 pytest + 33 script tests green. **Next: Phase 14 — Security hardening (IAM/KMS/Secrets/Cognito/WAF) per docs/roadmap.md.**

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
12. [x] **Phase 11 — Helm chart + Floci EKS (real k3s)** deployed (`51661a5`): pod Running, /health ok, upload via cluster → auto Lambda → PROCESSED; HPA live; known node-DNS quirk documented.
13. [x] Phase 7/8 finish — **inner-loop CI/CD LIVE** (`69fe882`): CodePipeline → CodeBuild (buildspec: ruff+pytest → Kaniko build+push) → CodeDeploy (`imageflow-onprem`, auto-rollback) end-to-end Succeeded; GitHub Actions deploy.yml + release.yml; setup-inner-loop.sh; ADR-10 deviation log (Kaniko).
14. [x] **Phase 12 — Deployment Strategies COMPLETE** (`6397127`): rolling (v2, 3 replicas, explicit strategy) → rollback (broken image → CrashLoop → `rollout undo` → v2 restored, revision trail) → canary (v3 slice, 38/42 split at 3+3 via in-cluster ClusterIP — port-forward pins on Floci) → blue/green (20/20 atomic selector flips + flip-back rollback). Chart strategy block, k8s/demo manifests, docs/deployment-strategies.md, scripts/demo-deploy-strategies.sh. **Floci CodeDeploy cannot do real blue/green/canary (simulated lifecycle) — Kubernetes strategies are the genuine demos.**
15. [x] **Phase 13 — Monitoring & Observability COMPLETE**: Prometheus pipeline metrics + CloudWatch custom metrics (API+Lambda) + optional CloudWatch Logs handler + Terraform alarms/EventBridge→SNS alerting, all live-verified on Floci; `scripts/observability.sh` + `docs/monitoring.md` + ADR-11. **Next: Phase 14 — Security (IAM/KMS/Secrets/Cognito/WAF), then reliability (15), GitOps (16), troubleshooting lab (17).**


## Blockers / Risks
- Context loss mid-session (context limit / daily cap / crash) — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); recovery via `git diff` + log tail.
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- Verify S3→Lambda event wiring on the installed Floci version during Phase 10; fallbacks: DynamoDB Streams → Lambda or direct boto3 invoke (`IMAGE_PROCESSING_TRIGGER` env var).
