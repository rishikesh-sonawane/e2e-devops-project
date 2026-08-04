# ImageFlow — The DevOps Operating System

> A single repository that grows with you from an empty folder to a production-inspired platform engineering portfolio — built **100% locally, 100% free**, on [Floci](https://floci.io), the MIT-licensed AWS emulator.

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

# 4. Run the API locally
cd ../app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload

# 5. Try it
curl -X POST -F "file=@photo.jpg" http://localhost:8000/api/v1/images
```

| Document | Purpose |
|---|---|
| [docs/setup.md](docs/setup.md) | Full free-tooling setup: Floci, AWS CLI, Terraform, Docker, kubectl, Helm, Freebuff + optional OpenCode Zen |
| [docs/architecture.md](docs/architecture.md) | Detailed architecture: ImageFlow, Floci deep-dive, CI/CD, IaC, security, observability |
| [docs/roadmap.md](docs/roadmap.md) | The 19-phase learning roadmap |
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
- ⬜ Phase 1 begins with the ImageFlow API foundation.
- See `.ai_memory/system_state.md` and `.ai_memory/active_task.md` for live status.
