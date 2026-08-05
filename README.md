# ImageFlow — The DevOps Operating System

> A single repository that grows with you from an empty folder to a production-inspired platform engineering portfolio — built **100% locally, 100% free**, on [Floci](https://floci.io), the MIT-licensed AWS emulator.

[![CI](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml/badge.svg)](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml)

---

## The Vision

**ImageFlow** is not just an application. It is a **DevOps Operating System**: a learning environment and portfolio asset where every phase of modern platform engineering — application development, containerization, CI/CD, infrastructure as code, cloud provisioning, orchestration, deployment strategies, monitoring, security, reliability, and GitOps — is built, operated, and troubleshot **on your own machine for free**.

The repository is a live, interview-ready artifact. By the end, you can walk into any AWS DevOps / Platform Engineering interview and say:

> *"I built it, I understand it, and I can troubleshoot it."*

## The 5 Core Principles

1. **Zero-cost, local-first** — Every AWS service runs inside Floci on `localhost:4566`. No cloud account, no auth tokens, no feature gates, no bills. Ever.
2. **Real fidelity, not mock theater** — Lambda, RDS, EKS (real k3s), ECS, EC2, ElastiCache, MSK, OpenSearch, and CodeBuild run as **real Docker containers**. Code verified locally behaves the same in production.
3. **Interview-driven** — Each roadmap phase requires theory, hands-on implementation, troubleshooting, security, and documentation before you move on.
4. **Documentation-first** — Architecture, roadmap, setup guides, and architectural decision records (ADRs) live in the repo.
5. **Memory-persistent AI collaboration** — Freebuff (with optional OpenCode Zen between sessions) stays contextually aligned across fresh sessions via the `.ai_memory/` bank and sync protocol.

## ImageFlow at a Glance

An **event-driven image pipeline**: upload → store → process → notify → retrieve.

```
                ┌──────────────┐         ┌───────────────────────────────────────────┐
  browser/curl  │  ImageFlow    │         │                Floci :4566                  │
   ───────────► │  API (FastAPI)│         │  S3 (originals + thumbnails)               │
                └──────┬───────┘         │  DynamoDB (metadata index)                  │
                       │ multipart       │  Lambda image-processor (real Docker,       │
                       ▼ upload          │    Pillow: thumbnail + metadata extraction) │
   ┌──────────────────────────────┐      │  SNS (image.processed events)               │
   │  S3 event notification        │────►│  API Gateway · IAM · CloudWatch             │
   └──────────────────────────────┘      │  EKS (k3s) · ECS · ECR · CodePipeline       │
                                         └───────────────────────────────────────────┘
```

**Processing flow**

1. Client uploads an image → `POST /api/v1/images` → FastAPI stores the original in **S3** and writes a `PENDING` record to **DynamoDB**.
2. An **S3 event notification** triggers the **Lambda** `image-processor` — a real Docker container running our Python (Pillow) code — which extracts metadata (format, dimensions, size, SHA-256), generates a thumbnail, and updates **S3 + DynamoDB** (`PROCESSED`).
3. The Lambda publishes an **SNS** event on completion.
4. `GET /api/v1/images/{id}` returns metadata plus pre-signed S3 URLs for the original and thumbnail.

> **Why this app?** It maximizes the DevOps + cloud footprint with minimal, deterministic Python: storage, serverless compute, event-driven architecture, NoSQL, messaging, IAM, and observability — all exercised for $0. The "heavy lifting" is done by the cloud architecture, not by thousands of lines of application code.

## Repository Structure

```text
.
├── .ai_memory/                 # AI memory bank (system state, active task, ADRs)
├── .github/workflows/          # Outer-loop CI/CD (GitHub Actions)
├── app/                        # ImageFlow API (FastAPI) + unit tests
├── lambda/
│   └── image-processor/        # Thumbnail/metadata Lambda (Pillow, image-backed)
├── terraform/                  # IaC: modules + environments (Floci S3/DDB backend)
├── helm/
│   └── imageflow/              # Helm chart for Floci EKS / ECS deployment
├── scripts/                    # deploy, health-check, cleanup, backup
├── tests/                      # Integration + e2e suites (Floci-backed)
├── docs/                       # architecture.md · roadmap.md · setup.md
├── docker-compose.yml          # Local dev services
├── floci-compose.yml           # Floci local cloud layer
├── Makefile                    # Common commands
├── AGENTS.md                   # AI agent operating rules + memory protocol
└── README.md                   # This file
```

## Quick Start

```bash
# 1. Start the local AWS cloud (Floci)
floci start                      # or: docker compose -f floci-compose.yml up -d
eval $(floci env)                # exports AWS_ENDPOINT_URL, dummy credentials, region

# 2. Verify the cloud is reachable
aws s3 mb s3://imageflow-check

# 3. Provision infrastructure (Terraform → Floci)
cd terraform
terraform init && terraform apply

# 4. Run the API locally (venv at the repo root)
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
uvicorn app.main:app --reload

# 5. Try it
curl -X POST -F "file=@photo.jpg" http://localhost:8000/api/v1/images
```

| Document | Purpose |
|---|---|
| [docs/setup.md](docs/setup.md) | Full free-tooling setup: Floci, AWS CLI, Terraform, Docker, kubectl, Helm, Freebuff + optional OpenCode Zen |
| [docs/architecture.md](docs/architecture.md) | Detailed architecture: ImageFlow, Floci deep-dive, CI/CD, IaC, security, observability |
| [docs/roadmap.md](docs/roadmap.md) | The 19-phase learning roadmap |
| [docs/source-control.md](docs/source-control.md) | Phase 2: branching strategy, commit conventions, PR workflow, release tagging |
| [docs/deployment-strategies.md](docs/deployment-strategies.md) | Phase 12: rolling / rollback / canary / blue-green demos on k3s |
| [docs/monitoring.md](docs/monitoring.md) | Phase 13: Prometheus /metrics + CloudWatch metrics/logs/alarms, SLIs/SLOs, demo runbook |
| [docs/security.md](docs/security.md) | Phase 14: IAM least-privilege, Secrets Manager + KMS, Cognito JWT, WAF, CI security gates, threat model |
| [docs/reliability.md](docs/reliability.md) | Phase 15: backup/restore drills with measured RTO, chaos/failure injection, auto-scaling reconciler, RPO/RTO |
| [AGENTS.md](AGENTS.md) | AI agent operating rules + memory sync protocol |
| `.ai_memory/` | Long-term project memory (state, tasks, ADRs) |

## The Roadmap at a Glance (Phases 0–19)

| # | Phase | # | Phase |
|---|---|---|---|
| 0 | Planning & Architecture | 10 | Cloud Infrastructure (S3, DynamoDB, Lambda, SNS, EC2, RDS…) |
| 1 | Application Foundation | 11 | Orchestration (Floci EKS k3s + ECS) |
| 2 | Source Control | 12 | Deployment Strategies |
| 3 | Linux Fundamentals | 13 | Monitoring & Observability |
| 4 | Bash & Automation | 14 | Security |
| 5 | Python for DevOps | 15 | Reliability Engineering |
| 6 | Code Quality | 16 | GitOps |
| 7 | Containerization | 17 | Troubleshooting Lab |
| 8 | CI/CD (dual-loop) | 18 | Documentation |
| 9 | Infrastructure as Code | 19 | Interview Preparation |

A phase is complete **only when you can confidently explain, implement, troubleshoot, and defend every decision.** Full details in [docs/roadmap.md](docs/roadmap.md).

## Current Status

- ✅ **Phase 0 (Planning & Architecture)** — this documentation set is the deliverable.
- ✅ **Phase 1 (Application Foundation)** — FastAPI ops endpoints live, tested (5/5), committed (`1706b26`).
- ✅ **Phase 2 (Source Control)** — workflow documented (`docs/source-control.md`) and practiced end-to-end (feature branch → conventional commits → squash merge → branch deleted). PR flow activates once a GitHub remote exists (Phase 8).
- ✅ **Phase 4 (Bash & Automation)** — all four operational scripts implemented + tested (26 tests), `scripts/lint.sh` shellcheck-clean.
- ✅ **Phase 7 kickoff / Phase 8 kickoff (CI-ready foundation)** — multi-stage non-root Dockerfile (build + smoke verified) and `.github/workflows/ci.yml` (ruff → pytest → shellcheck → docker build), validated locally with `act`.
- ✅ **CI LIVE & GREEN on GitHub** — real runs on every push (`ruff → shellcheck → pytest → docker build`). The first real run caught a shellcheck version skew (apt 0.9.0 vs brew 0.11.0) — fixed by pinning shellcheck v0.11.0 and verified passing. Badge above is live.
- ✅ **ImageFlow pipeline COMPLETE end-to-end + Terraform-provisioned** — upload (`POST /api/v1/images` → S3 + DynamoDB PENDING) · **process** (image-backed Lambda fires **automatically** via S3 event notification — Pillow thumbnail + metadata → `PROCESSED` + SNS `image.processed`; verified in ~5s) · retrieve (GET returns original + thumbnail presigned URLs). Terraform IaC (`terraform/`) provisions everything against Floci with S3 remote state + DynamoDB locking (`9b745dc`).
- ✅ **Phase 11 — Kubernetes deployment LIVE** — the API also runs in **Floci EKS (real k3s)** via the `helm/imageflow` chart (Deployment, Service, ConfigMap, Secret, HPA). Uploads through the clustered API get auto-processed by the Lambda. Two deployment targets: serverless + Kubernetes (`51661a5`).
- ✅ **Phase 7/8 — Inner-loop CI/CD LIVE** — **CodePipeline → CodeBuild → CodeDeploy** end-to-end on Floci (`69fe882`). CodeBuild runs the real buildspec (ruff + pytest gates → **Kaniko daemonless** image build + push to ECR); CodeDeploy targets an on-premises deployment group with auto-rollback. Three deployment paths now: serverless, Kubernetes, and CI/CD pipeline (ADR-10 logs the Kaniko deviation). GitHub Actions `deploy.yml` + `release.yml` complete the outer loop.
- ✅ **Phase 12 — Deployment Strategies COMPLETE** — all four strategies **proven live on the k3s cluster** (`6397127`): **rolling** (chart now ships explicit RollingUpdate, maxSurge 1 / maxUnavailable 0), **rollback** (broken image → CrashLoop → `kubectl rollout undo` → v2 restored), **canary** (v3 slice measured at **38/42 ≈ 50/50** with 3+3 pods via in-cluster ClusterIP), and **blue/green** (atomic Service selector flip: 20/20 v2 → 20/20 v3 → flip back). Reproduce with `scripts/demo-deploy-strategies.sh`; full write-up + Floci CodeDeploy caveat in `docs/deployment-strategies.md`.
- ✅ **Phase 13 — Monitoring & Observability COMPLETE** — three observability planes live and probe-verified: **Prometheus `/metrics`** (pipeline counters + upload-latency histogram), **CloudWatch custom metrics** (namespace `ImageFlow`: API emits `Uploads`/`UploadErrors`, Lambda emits `ProcessedCount`/`FailedCount`), **CloudWatch Logs** (optional handler → `/imageflow/api`), and **alerting** (Terraform alarms `imageflow-failed-images` + `imageflow-upload-errors` → SNS via EventBridge rule). Inspect with `scripts/observability.sh`; full write-up + demo runbook in `docs/monitoring.md`. Floci stores alarm state but not alarm actions — documented in ADR-11.
- ✅ **Phase 14 — Security Hardening COMPLETE** — probe-verified + live on Floci: **KMS** key/alias with encrypt→decrypt round trip, **Secrets Manager** (`imageflow/app-secret`) with **secrets-backed credential resolution** (`IMAGEFLOW_SECRET_NAME`), **Cognito** full auth flow with real JWT claims, **WAF v2** web ACL (rate-limit + managed rules), **least-privilege IAM** user + tightened Lambda policy, `scripts/security-audit.sh` (secret scan + IAM review), and **CI gates** (pip-audit + gitleaks + trivy fs/image). Full write-up + threat model in `docs/security.md` (ADR-12). Floci validates SigV4 but doesn't enforce IAM authorization — documented honestly.
- ✅ **Phase 15 — Reliability Engineering COMPLETE** — `scripts/reliability.sh` drives the full story live on Floci: **backup** (paginated DynamoDB export + S3 sync → `data/backups/cloud-<ts>/` with manifest) · **restore** (batch-write + sync + count verification) · **drill** (backup → simulated loss → restore → verify → **measured RTO**, RPO=0 for the drill) · **chaos** (`kill-pod` → Deployment controller self-heals on k3s; `kill-instance` → **ASG Auto Scaling replacement** in ~9s; `kill-api` → process restart; `fail-image` → Lambda FAILED dead-letter → fix + replay S3 event → PROCESSED) · **scaling** (live HPA + Deployment reconcilers + ASG instance count) · **reconcile [--apply]** (explicit desired-vs-actual loop over ASG + Deployment + HPA). Terraform `autoscaling` module provisions `imageflow-asg` (launch-template backed — the ASG reconciler is genuinely live; launch *configurations* fail on Floci). Full write-up + demo runbook in `docs/reliability.md` (ADR-13).
- See `.ai_memory/system_state.md` and `.ai_memory/active_task.md` for live status.
