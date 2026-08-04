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

## Component Status
- [x] Phase 0 — Planning & Architecture (docs aligned to a single vision: README, docs/, AGENTS.md, .ai_memory/)
- [x] AI collaboration setup documented (Freebuff primary + OpenCode Zen occasional, ADR-08)
- [x] Directory Skeleton + .gitignore Created
- [ ] Application Code (FastAPI + boto3 for S3/DynamoDB/Lambda/SNS)
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
