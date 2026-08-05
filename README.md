# 🚀 ImageFlow — The DevOps Operating System

> **A production-inspired platform engineering project — built end-to-end on your own laptop, for $0.**  
> An event-driven image pipeline wrapped in *everything* a real DevOps platform needs: Terraform infrastructure, a real Kubernetes cluster, dual-loop CI/CD, observability, security hardening, and reliability engineering — all verified live, all documented, all free.

[![CI](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml/badge.svg)](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-54%20pytest%20%2B%2059%20script-green)](tests/)
[![Security](https://img.shields.io/badge/security-pip--audit%20%7C%20gitleaks%20%7C%20trivy-blue)]()
[![IaC](https://img.shields.io/badge/IaC-Terraform-purple)]()
[![Orchestration](https://img.shields.io/badge/Orchestration-Kubernetes%20%2B%20Helm-326CE5)]()
[![Cost](https://img.shields.io/badge/cost-%240.00%2Fmonth-brightgreen)]()
[![License](https://img.shields.io/badge/license-MIT-orange)]()

---

## 🎯 Why this project exists

**ImageFlow is not just an application — it is a *DevOps Operating System*:** a learning environment and portfolio asset where every discipline of modern platform engineering is built, operated, broken, fixed, and documented — on your own machine, forever free.

- **19 phases** of a mastery roadmap — from Git fundamentals to deployment strategies, security, reliability engineering, and GitOps
- **Real cloud services, not mock theater** — Floci (the MIT-licensed AWS emulator) runs actual Docker containers: a **real k3s Kubernetes cluster**, **real Lambda functions**, a **real container registry**, **real EC2 auto-scaling**
- **The same professional tooling** — AWS CLI, boto3, Terraform, Helm, kubectl, GitHub Actions, CodePipeline/CodeBuild/CodeDeploy — all working unchanged against `localhost:4566`
- **$0 forever** — no cloud account, no credit card, no bills, no blast radius. A mistake costs nothing but a retry.

> ### The mission statement
> ```text
> "I built it, I understand it, and I can troubleshoot it."
> ```
> That's the sentence every phase of this project is working toward — the honest, demonstrable claim of a real platform engineer.

---

## 🧠 What you'll learn here (if you're an aspiring DevOps engineer)

This repository is a **free, self-contained DevOps curriculum** with a working system at the end of every phase. Follow the [19-phase roadmap](docs/roadmap.md) and you'll build, in order:

| Discipline | What you'll master | Where |
|---|---|---|
| 🐧 **Fundamentals** | Git, Linux, Python, Bash scripting, shellcheck-grade automation | [docs/roadmap.md](docs/roadmap.md) Phases 1–6 |
| 🐳 **Containerization** | Multi-stage non-root Docker builds, image hygiene, `.dockerignore` | [Dockerfile](Dockerfile) |
| 🔁 **CI/CD** | GitHub Actions (outer loop) **+** CodePipeline→CodeBuild→CodeDeploy (inner loop), daemonless **Kaniko** builds, auto-rollback | [`.github/workflows/`](.github/workflows/), [docs/setup.md](docs/setup.md) |
| 🧱 **Infrastructure as Code** | Terraform modules, remote state + locking, idempotent plans | [terraform/](terraform/) |
| ☸️ **Orchestration** | Real Kubernetes (k3s), Helm charts, HPA, rolling/rollback/canary/blue-green **proven live** | [helm/imageflow](helm/imageflow), [docs/deployment-strategies.md](docs/deployment-strategies.md) |
| 📊 **Observability** | Prometheus metrics, CloudWatch metrics/logs/alarms, EventBridge alerting, SLI/SLO thinking | [docs/monitoring.md](docs/monitoring.md) |
| 🔐 **Security** | KMS, Secrets Manager, Cognito JWT auth, WAF v2, least-privilege IAM, dependency/image scanning in CI | [docs/security.md](docs/security.md) |
| 🛡️ **Reliability** | Backup/restore drills with **measured RTO/RPO**, chaos engineering, auto-scaling reconcilers | [docs/reliability.md](docs/reliability.md) |

**Every phase is graded by the same bar:** *explain it, implement it, troubleshoot it, defend it* — and the repo ships a [manual verification runbook](docs/manual-verification.md) so you (or an interviewer) can watch each layer work live.

---

## 🏗️ The architecture at a glance

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Local Development Machine                       │
│                                                                          │
│  ┌───────────────────┐        ┌──────────────────────────────────────┐  │
│  │   ImageFlow API    │        │           Floci (:4566)              │  │
│  │    (FastAPI)       │        │   THE LOCAL CLOUD — AWS emulator     │  │
│  │                    │        │  ┌────────────────────────────────┐  │  │
│  │  /health /version  │        │  │  S3        (file warehouse)    │  │  │
│  │  /metrics /config  │        │  │  DynamoDB  (fast catalogue)    │  │  │
│  │  /api/v1/images    │        │  │  Lambda    (REAL docker worker) │  │  │
│  └────────┬──────────┘        │  │  SNS       (event loudspeaker)  │  │  │
│           │  multipart upload │  │  EKS       (REAL k3s cluster)   │  │  │
│           ▼                   │  │  ECR       (REAL registry)      │  │  │
│  ┌───────────────────┐        │  │  EC2/ASG   (REAL auto-scaling)  │  │  │
│  │  S3 event          │──────▶│  │  KMS · Secrets · Cognito · WAF  │  │  │
│  │  notification      │        │  │  CloudWatch · CodePipeline ·   │  │  │
│  └───────────────────┘        │  │  CodeBuild · CodeDeploy         │  │  │
│                               │  └────────────────────────────────┘  │  │
│  IaC: Terraform (state in S3 + DDB locking)      CI/CD: dual-loop      │  │
└──────────────────────────────────────────────────────────────────────────┘
```

### The pipeline in one breath

```text
POST /api/v1/images ──▶ S3 stores original ──▶ DynamoDB "PENDING" record
        │
        ▼
S3 event notification ──▶ Lambda (Pillow) ──▶ thumbnail + metadata
        │                                          │
        ▼                                          ▼
DynamoDB "PROCESSED" ◀─────────────── SNS "image.processed" announcement
```

A user uploads a photo; ~5 seconds later it's processed, thumbnailed, catalogued, and announced — **automatically, no human in the loop**. That's event-driven architecture you can watch with your own eyes.

---

## ⚙️ What's inside (the full surface)

| Layer | Delivered | Proof |
|---|---|---|
| **Application** | FastAPI (Python 3.12) — upload/get/list images, health, version, Prometheus metrics, masked config | `app/` + 36 unit tests |
| **Serverless** | Real Docker-backed Lambda: Pillow thumbnails + metadata + FAILED dead-letter | `lambda/image-processor/` + 17 tests |
| **IaC** | 7 Terraform modules (storage, database, messaging, compute, observability, security, autoscaling) with S3 remote state + DynamoDB locking | `terraform/` — idempotent plan |
| **Orchestration** | Helm chart → real k3s cluster; HPA auto-scaling; 4 deployment strategies proven live | `helm/imageflow`, `k8s/demo/` |
| **CI/CD** | GitHub Actions (lint→test→build→security gates) + CodePipeline→CodeBuild (Kaniko)→CodeDeploy | `.github/workflows/`, `buildspec.yml`, `appspec.yml` |
| **Observability** | Prometheus `/metrics` + CloudWatch metrics/logs/alarms + EventBridge→SNS alerting | `scripts/observability.sh` |
| **Security** | KMS encryption, Secrets Manager (app can source creds from it), Cognito real JWTs, WAF v2, least-privilege IAM, CI gates (pip-audit/gitleaks/trivy) | `scripts/security.sh` + `security-audit.sh` |
| **Reliability** | Backup/restore drills with measured RTO, chaos injection (kill pod/instance/API/image), auto-scaling reconciler | `scripts/reliability.sh` + 17 tests |
| **Ops scripts** | 18 shellcheck-clean operational scripts (incl. CodeDeploy hooks), all behavior-tested | `scripts/` + 59 script tests |

### Quality gates (all green)

- ✅ **54 Python tests** (36 app + 17 Lambda + 1 live integration) · **59 shell-script behavior tests** across 7 suites
- ✅ **ruff** clean (Python style) · **shellcheck** clean (shell style) · **Terraform validate/fmt** clean · **helm lint** clean
- ✅ **CI on every push**: lint & static checks → unit tests → Docker build (trivy-scanned) → security gates (pip-audit + gitleaks + trivy filesystem)
- ✅ **Idempotent infrastructure**: `terraform plan` = *"No changes"* — the blueprint matches reality

---

## 🚀 Quick start (60 seconds to a running pipeline)

```bash
# 1. Install the free toolchain (see docs/setup.md): Floci, AWS CLI, Terraform, Docker, kubectl, Helm

# 2. Start the local cloud
floci start && eval $(floci env)          # AWS at localhost:4566, creds test/test

# 3. Provision infrastructure
bash scripts/push-lambda.sh               # build + push the Lambda image to Floci ECR
terraform -chdir=terraform/environments/dev apply -auto-approve

# 4. Run the API
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
uvicorn app.main:app --port 8000

# 5. Watch the pipeline work
curl -s -F "file=@photo.jpg" http://localhost:8000/api/v1/images
# ~5s later the record flips PENDING → PROCESSED with a thumbnail, automatically.
```

**Then prove it end-to-end by hand** — every layer, with expected outputs: [`docs/manual-verification.md`](docs/manual-verification.md).

---

## 📚 Documentation (the repo is documentation-first)

| Document | What it is |
|---|---|
| [docs/architecture.md](docs/architecture.md) | The technical blueprint — components, data flow, design decisions, AWS↔Floci mapping |
| [docs/roadmap.md](docs/roadmap.md) | The 19-phase mastery roadmap — what's done, what's next, how to know you're done |
| [docs/setup.md](docs/setup.md) | The free-tooling installation guide (Floci, AWS CLI, Terraform, Docker, kubectl, Helm) |
| [docs/DEVELOPER.md](docs/DEVELOPER.md) | The developer's guide — repo map, dev loop, testing, conventions, contributing |
| [docs/source-control.md](docs/source-control.md) | Git workflow: GitHub Flow, conventional commits, squash merges, release tags |
| [docs/deployment-strategies.md](docs/deployment-strategies.md) | Rolling / rollback / canary / blue-green — proven live on k3s |
| [docs/monitoring.md](docs/monitoring.md) | Prometheus + CloudWatch: metrics, logs, alarms, SLI/SLO thinking |
| [docs/security.md](docs/security.md) | KMS, Secrets Manager, Cognito, WAF, IAM, CI gates, threat model |
| [docs/reliability.md](docs/reliability.md) | RTO/RPO drills, chaos engineering, auto-scaling reconcilers |
| [docs/manual-verification.md](docs/manual-verification.md) | Run the whole system by hand and verify every layer |
| [AGENTS.md](AGENTS.md) | How AI assistants operate in this repo (memory sync, ADRs, safety rules) |

---

## 📁 Repository structure

```text
.
├── app/                    # ImageFlow API (FastAPI) + unit tests
├── lambda/image-processor/ # Thumbnail Lambda (Pillow, real Docker image)
├── terraform/              # IaC: 7 modules + dev environment (S3/DDB backend)
├── helm/imageflow/         # Helm chart → Floci EKS (real k3s)
├── k8s/demo/               # Canary + blue/green manifests (Phase 12)
├── scripts/                # 18 operational scripts + 7 test suites
├── .github/workflows/      # Outer-loop CI/CD (GitHub Actions) — ci.yml · deploy.yml · release.yml
├── Dockerfile · buildspec.yml · appspec.yml   # Build + pipeline instruction files
├── tests/                  # Integration tests (Floci-backed)
├── docs/                   # All documentation (table above)
├── .ai_memory/             # AI session memory (state, tasks, ADRs)
└── floci-compose.yml       # Optional docker-compose Floci layer
```

---

## 🗺️ Project status — where we are

**15 of 19 roadmap phases complete** — everything below is built, tested, and verified live:

- ✅ Phases 0–2, 4 — planning, source control, Bash automation
- ✅ Phases 7–11 — containers, CI/CD (dual-loop), Terraform IaC, cloud infra, **real k3s + Helm**
- ✅ Phase 12 — **all four deployment strategies proven live** on the cluster
- ✅ Phase 13 — observability: metrics, logs, alarms, alerting
- ✅ Phase 14 — security hardening: KMS, Secrets Manager, Cognito JWTs, WAF, CI gates
- ✅ Phase 15 — reliability: measured RTO drills, chaos injection, auto-scaling reconcilers
- 🔜 **Phase 16 — GitOps** (Flux/ArgoCD-style declarative sync) — next up
- ⬜ Phases 3, 5, 17–19 — Linux fundamentals, Python for DevOps, troubleshooting lab, interview prep (deferred/planned)

**Honesty is a feature:** every emulator limitation is documented (e.g., Floci validates SigV4 but doesn't enforce IAM authorization; CodeDeploy lifecycle is simulated). Real-AWS-correct design + honest local limits = a credible portfolio.

---

## 🤝 Contributing & learning

- New to the repo? Start with **[docs/DEVELOPER.md](docs/DEVELOPER.md)** — the developer's guide.
- Want the full learning path? Read **[docs/roadmap.md](docs/roadmap.md)**.
- Found something that could be better? Open an issue or PR — contributions follow [docs/source-control.md](docs/source-control.md).

---

## 📜 License

[MIT](LICENSE) — free to learn from, free to build on, free to fork. Built with [Floci](https://floci.io), the MIT-licensed AWS emulator. **Total cloud spend: $0.00.**
