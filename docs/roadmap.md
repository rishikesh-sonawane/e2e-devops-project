# ImageFlow — DevOps Mastery Roadmap

## Goal

Build a production-inspired DevOps ecosystem from scratch while mastering every concept required for AWS DevOps, Platform Engineering, and Cloud Infrastructure interviews. **Everything runs locally and for free on Floci** (`localhost:4566`).

Every milestone must include:

- Theory & fundamentals
- Hands-on implementation
- Architecture understanding
- Troubleshooting
- Security considerations
- Performance optimization
- Best practices
- Interview preparation
- Documentation

A milestone is complete **only when you can confidently explain, implement, troubleshoot, and defend every decision.**

---

## Phase 0 — Planning & Architecture ✅ (complete)

Before writing code:

- Define project scope
- Design the high-level architecture (see `docs/architecture.md`)
- Identify system components and interactions
- Create architecture diagrams
- Plan repository structure and branching strategy
- Define deployment, release, and rollback strategy
- **Select cloud emulator — Floci (floci.io), MIT-licensed, 69 AWS services, port 4566**

**Deliverables (all in this repo):**
- Architecture document ✅ `docs/architecture.md`
- Repository structure ✅ `README.md`
- Free-tooling setup ✅ `docs/setup.md`
- AI operating rules ✅ `AGENTS.md` + `.ai_memory/`
- Floci integration plan (env vars, service mapping, storage modes) ✅

---

## Phase 1 — Application Foundation

Understand:
- Application architecture, REST APIs, HTTP fundamentals
- Request lifecycle, error handling, logging
- Configuration management, environment variables, secrets
- Dependency management

Build (ImageFlow API):
- `GET /health` — liveness probe
- `GET /version` — Git SHA, build timestamp
- `GET /metrics` — Prometheus format
- `GET /config` — configuration dump
- Unit tests for all endpoints

Interview Topics: REST APIs, HTTP methods, status codes, stateless architecture, logging strategies, configuration management.

---

## Phase 2 — Source Control

Master: Git fundamentals, branching, merging, rebasing, cherry-picking, reset vs revert, tags, releases, conflict resolution, Git internals.

Project: branching strategy (`feature/*`), pull request workflow, commit conventions, release tagging.

Interview Topics: merge vs rebase, fast-forward merges, detached HEAD, Git object model.

---

## Phase 3 — Linux Fundamentals

Master: filesystem, permissions, users/groups, processes, services, networking, logs, system monitoring, scheduling, package management.

Hands-on: service management, process debugging, file permissions, log analysis, resource monitoring (also useful for the Floci EC2 containers).

Troubleshooting: high CPU, memory issues, disk issues, service failures, network failures.

Interview Topics: signals, zombie processes, hard vs soft links, file descriptors, boot process.

---

## Phase 4 — Bash & Automation

Master: variables, loops, functions, arrays, conditions, exit codes, pipes, redirection, text processing, error handling.

Build (`scripts/`):
- `deploy.sh` — deployment script
- `health-check.sh` — health check script
- `cleanup.sh` — resource cleanup
- `backup.sh` — backup script

Interview Topics: exit codes, process substitution, command substitution, shell expansion.

---

## Phase 5 — Python for DevOps

Master: file operations, JSON, YAML, APIs, HTTP requests, logging, exception handling, CLI development, virtual environments.

Build: automation utilities, API clients, configuration parsers, CLI tools — all Python 3.12, pinned to `app/requirements.txt`.

Interview Topics: when to use Bash vs Python, error handling, packaging.

---

## Phase 6 — Code Quality

Implement: formatting (Ruff/Black), linting (Ruff), unit testing (pytest), code coverage, static analysis (mypy), dependency validation (pip-audit / pip-tools).

Interview Topics: shift left, quality gates, test pyramid.

---

## Phase 7 — Containerization

Master: containers, images, layers, registries, volumes, networking, image optimization, multi-stage builds, runtime security.

Build:
- Production-ready multi-stage Dockerfile for the API (non-root, HEALTHCHECK)
- Dockerfile for the `image-processor` Lambda (Pillow, image-backed)
- Push/pull images via **Floci ECR** (real OCI registry)

Interview Topics: containers vs VMs, ENTRYPOINT vs CMD, copy-on-write, image layers.

---

## Phase 8 — CI/CD

Master: pipeline architecture, build/test/release workflows, artifact management, versioning, rollbacks, approvals, secrets, parallel execution, matrix builds, reusable workflows.

Build (dual-loop):
- **Outer loop (GitHub Actions):** `.github/workflows/ci.yml` (quality + Floci-backed tests + build), `deploy.yml`, `release.yml`
- **Inner loop (Floci):** CodePipeline orchestration, CodeBuild real `buildspec` execution, CodeDeploy deployment groups

Interview Topics: blue/green, canary, rolling deployments, feature flags, pipeline optimization.

---

## Phase 9 — Infrastructure as Code

Master: declarative infrastructure, state, modules, variables, outputs, workspaces, drift detection, lifecycle rules, remote state, locking.

Build (Terraform/OpenTofu + Floci):
- `terraform/backend.tf` — S3 remote state + DynamoDB locking
- Modules: `storage`, `database`, `compute`, `messaging`, `iam`, `networking`
- Environments: `dev/` and `ci/`
- Provision S3 buckets, DynamoDB table + Streams, Lambda + S3 trigger, SNS topic, IAM roles

Interview Topics: state corruption, drift, module design, lifecycle rules.

---

## Phase 10 — Cloud Infrastructure

Master: networking, identity, compute, storage, load balancing, scaling, security, high availability, disaster recovery, cost optimization.

Build (ImageFlow core + expansion):
- Core: S3 (uploads, thumbs, state, logs), DynamoDB + Streams, Lambda (real Docker), SNS, IAM
- Expansion (Floci real Docker): EC2 — real Linux containers with SSH, UserData, IMDS; ELB v2 — ALB/NLB with target groups; RDS — real PostgreSQL; ElastiCache — real Valkey/Redis; Auto Scaling — launch configs, ASGs, lifecycle hooks

Interview Topics: networking scenarios, security scenarios, scaling scenarios, HA design.

---

## Phase 11 — Orchestration

Master: pods, deployments, services, ingress, ConfigMaps, secrets, volumes, autoscaling, scheduling, networking, storage, controllers.

Build:
- **Floci EKS** — real k3s cluster: deploy ImageFlow via `helm/imageflow` (Deployment, Service, Ingress, ConfigMap, Secret, HPA)
- **Floci ECS** — real container tasks: task definitions, services, capacity providers
- Scale application, rolling updates, self-healing verification

Interview Topics: CrashLoopBackOff, pending pods, ImagePullBackOff, DNS failures.

---

## Phase 12 — Deployment Strategies

Implement:
- Rolling updates via Floci ECS/EKS
- Blue/green via Floci CodeDeploy (traffic shifting)
- Canary via Floci CodeDeploy + ELB target groups
- Rollback via CodeDeploy auto-rollback
- Progressive delivery discussion

Interview Topics: deployment failures, rollback strategy, release validation.

---

## Phase 13 — Monitoring & Observability

Master: metrics, logs, tracing, dashboards, alerting, SLI, SLO, error budgets.

Build:
- Application monitoring: Prometheus `/metrics` + Floci CloudWatch Metrics/Logs
- Infrastructure monitoring: Floci CloudWatch + OpenSearch (real engine)
- Alerting: CloudWatch Alarms → EventBridge / SNS
- Incident dashboards: OpenSearch + floci-ui

Interview Topics: Golden Signals, RED, USE, MTTR.

---

## Phase 14 — Security

Master: identity, secrets, encryption, least privilege, supply chain security, image scanning, dependency scanning, policy enforcement, compliance.

Build:
- IAM roles/policies via Floci IAM + STS (real SigV4 auth)
- Secrets via Floci Secrets Manager + KMS
- Encryption via Floci KMS
- Cognito user pools via Floci Cognito
- WAF via Floci WAF v2; certificates via Floci ACM
- CI security gates: Trivy image scan, pip-audit, SAST

Interview Topics: security in CI/CD, secrets management, IAM design.

---

## Phase 15 — Reliability Engineering

Master: availability, scalability, resiliency, fault tolerance, disaster recovery, capacity planning.

Build (failure + recovery testing on Floci):
- Kill EC2 container, crash RDS, drain ECS tasks
- Recovery: Auto Scaling replacement, Lambda retries/DLQ
- Performance: load against local S3, DynamoDB, Lambda
- Chaos: stop containers, exhaust SQS, rotate IAM keys

Interview Topics: RTO, RPO, chaos engineering, circuit breakers.

---

## Phase 16 — GitOps

Master: declarative deployments, pull model, sync, drift detection, policy, promotion, environment management.

Build:
- GitOps with Floci EKS (k3s + ArgoCD/Flux)
- Declarative infrastructure via Terraform + Floci
- Environment promotion via Floci CodePipeline

Interview Topics: push vs pull, drift, promotion strategies.

---

## Phase 17 — Troubleshooting Lab

Simulate failures across Floci services. Every issue needs: Symptoms → Root Cause → Investigation → Resolution → Prevention.

- Broken deployment (ECS/EKS task crash, CodePipeline failure)
- High CPU (EC2 container stress test)
- Memory leak (Lambda container OOM)
- Network failures (Floci container restart, port conflicts)
- Permission issues (IAM policy deny, STS token expiry)
- Pipeline failures (CodeBuild timeout, CodeDeploy hook failure)
- Certificate failures (ACM expiry)
- Scaling failures (ASG max instances, EKS node limits)
- Storage failures (RDS crash, S3 bucket policy denial, DynamoDB throttling)
- Configuration issues (broken ConfigMap, bad Lambda env vars)

---

## Phase 18 — Documentation

Create: architecture document (done), runbooks, operational guides, deployment guide, troubleshooting guide, incident response guide, interview notes, lessons learned.

---

## Phase 19 — Interview Preparation

For **every topic**, prepare:

### Fundamentals
Core concepts, definitions, best practices.

### Technical Questions
Beginner, intermediate, advanced.

### Scenario Questions
Real-world troubleshooting, design decisions, failure analysis.

### Architecture Questions
Whiteboard designs, scaling discussions, security reviews.

### Behavioral Stories
Cost optimization, CI/CD improvements, incident response, automation, migration, developer productivity, cross-team collaboration, on-call, production issues.

### Follow-up Questions
Practice handling probing questions until you answer naturally — no memorized responses.

---

## Completion Criteria (When You Move On)

A phase is complete only if you can:

- Explain the concepts clearly from first principles.
- Implement the solution without following a tutorial.
- Troubleshoot common failures systematically.
- Discuss trade-offs and design choices.
- Apply security and best practices.
- Relate the concepts to professional experience.
- Answer beginner, intermediate, and advanced interview questions.
- Handle follow-up questions confidently.
- Document your implementation and lessons learned.

If you cannot do all of the above, you stay on that phase until you can.

---

## The Mindset

This isn't about finishing a checklist quickly. It's about building a level of understanding where you can walk into an interview and think:

> *"Whatever they ask — fundamentals, implementation, troubleshooting, architecture, or scenarios — I have either done it, understood it deeply, or can reason through it logically."*

That's the standard we're aiming for.
