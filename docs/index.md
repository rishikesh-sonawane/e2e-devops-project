# ImageFlow — The DevOps Operating System

> **A production-inspired platform engineering project — built end-to-end on your own laptop, for $0.**  
> An event-driven image pipeline wrapped in *everything* a real DevOps platform needs: Terraform infrastructure, a real Kubernetes cluster, dual-loop CI/CD, observability, security hardening, and reliability engineering — all verified live, all documented, all free.

[![CI](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml/badge.svg)](https://github.com/rishikesh-sonawane/e2e-devops-project/actions/workflows/ci.yml)
[![Cost](https://img.shields.io/badge/cost-%240.00%2Fmonth-brightgreen)]()
[![License](https://img.shields.io/badge/license-MIT-orange)](https://github.com/rishikesh-sonawane/e2e-devops-project/blob/main/LICENSE)

---

## 📚 Browse the documentation

| Section | What you'll find |
|---|---|
| **[:material-rocket-launch: Get Started](setup.md)** | Install the free toolchain (Floci, AWS CLI, Terraform, Docker, kubectl, Helm) |
| **[:material-map: Architecture](architecture.md)** | The system in one paragraph, design decisions, data model, honest Floci limits, interview talking points |
| **[:material-format-list-checks: Manual Verification Runbook](manual-verification.md)** | Run and verify **every layer of the system by hand** — the definitive proof |
| **[:material-code-tags: Developer Guide](DEVELOPER.md)** | Repo map, dev loop, testing matrix, conventions, troubleshooting |
| **[:material-sign-direction: 19-Phase Roadmap](roadmap.md)** | The complete DevOps mastery curriculum — what's done, what's next |
| **[:material-source-branch: Source Control](source-control.md)** | Git workflow: GitHub Flow, conventional commits, squash merges |
| **[:material-kubernetes: Deployment Strategies](deployment-strategies.md)** | Rolling / rollback / canary / blue-green — proven live on a real k3s cluster |
| **[:material-chart-line: Monitoring & Observability](monitoring.md)** | Prometheus + CloudWatch metrics, logs, alarms, SLI/SLO thinking |
| **[:material-lock: Security](security.md)** | KMS, Secrets Manager, Cognito JWT, WAF, IAM, CI security gates |
| **[:material-shield-check: Reliability](reliability.md)** | Measured RTO/RPO drills, chaos engineering, auto-scaling reconcilers |

---

## ⚡ The pipeline in one breath

```text
POST /api/v1/images ──▶ S3 stores original ──▶ DynamoDB "PENDING" record
        │
        ▼
S3 event notification ──▶ Lambda (Pillow) ──▶ thumbnail + metadata
        │                                          │
        ▼                                          ▼
DynamoDB "PROCESSED" ◀─────────────── SNS "image.processed" announcement
```

A user uploads a photo; ~5 seconds later it's processed, thumbnailed, catalogued, and announced — **automatically, no human in the loop**.

---

## ✅ Project status

**15 of 19 roadmap phases complete** — everything below is built, tested, and verified live:

- ✅ Phases 0–2, 4 — planning, source control, Bash automation
- ✅ Phases 7–11 — containers, CI/CD (dual-loop), Terraform IaC, cloud infra, real k3s + Helm
- ✅ Phase 12 — all four deployment strategies proven live on the cluster
- ✅ Phase 13 — observability: metrics, logs, alarms, alerting
- ✅ Phase 14 — security hardening: KMS, Secrets Manager, Cognito JWTs, WAF, CI gates
- ✅ Phase 15 — reliability: measured RTO drills, chaos injection, auto-scaling reconcilers
- 🔜 **Phase 16 — GitOps** (Flux/ArgoCD-style declarative sync) — next up
- ⬜ Phases 3, 5, 17–19 — Linux fundamentals, Python for DevOps, troubleshooting lab, interview prep

**Honesty is a feature:** every emulator limitation is documented (e.g., Floci validates SigV4 but doesn't enforce IAM authorization). Real-AWS-correct design + honest local limits = a credible portfolio.

---

## 🚀 Quick start (60 seconds to a running pipeline)

```bash
floci start && eval $(floci env)          # start the local cloud
bash scripts/push-lambda.sh               # build + push the Lambda image to Floci ECR
terraform -chdir=terraform/environments/dev apply -auto-approve   # provision everything
source .venv/bin/activate && pip install -r app/requirements.txt
uvicorn app.main:app --port 8000          # run the API
curl -s -F "file=@photo.jpg" http://localhost:8000/api/v1/images   # watch it process
```

---

## 📜 License

[MIT](https://github.com/rishikesh-sonawane/e2e-devops-project/blob/main/LICENSE) — free to learn from, free to build on, free to fork. Built with [Floci](https://floci.io). **Total cloud spend: $0.00.**
