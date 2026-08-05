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

Project: branching strategy (`feature/*`), pull request workflow, commit conventions, release tagging — **all defined in `docs/source-control.md`** ✅ (the Phase 2 deliverable; practiced locally — the PR flow activates once a GitHub remote exists, Phase 8).

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

> **Phase 4 complete** ✅ — all four scripts implemented with behavior tests (26/26), `scripts/lint.sh` shellcheck-clean, merged as `434a333`. Sequence: skeleton (`1d5c3d5`) → health-check (`8cb61ea`) → full suite (`434a333`).

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

> Kickoff ✅ — `Dockerfile` (multi-stage, non-root `imageflow`, HEALTHCHECK) + `.dockerignore` built & smoke-verified; `docker build -t imageflow-api:ci .` passes.

---

## Phase 8 — CI/CD

Master: pipeline architecture, build/test/release workflows, artifact management, versioning, rollbacks, approvals, secrets, parallel execution, matrix builds, reusable workflows.

Build (dual-loop):
- **Outer loop (GitHub Actions):** `.github/workflows/ci.yml` (quality + Floci-backed tests + build), `deploy.yml`, `release.yml`
- **Inner loop (Floci):** CodePipeline orchestration, CodeBuild real `buildspec` execution, CodeDeploy deployment groups

Interview Topics: blue/green, canary, rolling deployments, feature flags, pipeline optimization.

> Kickoff ✅ — `.github/workflows/ci.yml` (quality=ruff+shellcheck+toml → test=pytest → build=Docker image) written and validated locally with `act` (reviewer-found GHA-cache permissions bug fixed). Goes live when the repo gains a GitHub remote. Inner loop (Floci CodePipeline/CodeBuild/CodeDeploy) comes later in this phase.

---

## Phase 9 — Infrastructure as Code

Master: declarative infrastructure, state, modules, variables, outputs, workspaces, drift detection, lifecycle rules, remote state, locking.

Build (Terraform + Floci):
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

> Core ✅ — full pipeline live end-to-end AND Terraform-provisioned (`9b745dc`): upload/get/list (`9e941dd`) + image-backed Lambda (`2065ff1`, Pillow thumbnail + metadata → PROCESSED + SNS image.processed) with **automatic S3-event delivery** (PROCESSED in ~5s). Terraform modules + environments/dev provision S3/DynamoDB/SNS/IAM/ECR/Lambda with Floci S3 remote state + DynamoDB locking; plan idempotent. **Phase 11 ✅ (`51661a5`)** — API also deployed to Floci EKS (real k3s) via helm/imageflow (Deployment/Service/ConfigMap/Secret/HPA); cluster→Floci connectivity + auto-processing verified. **Phase 7/8 inner loop ✅ (`69fe882`)** — CodePipeline → CodeBuild (ruff+pytest → **Kaniko daemonless** build+push) → CodeDeploy (`imageflow-onprem`, auto-rollback) end-to-end Succeeded; GitHub Actions deploy/release workflows; `scripts/setup-inner-loop.sh`; ADR-10 deviation log. **Phase 12 ✅ (`6397127`)** — deployment strategies proven live on k3s (rolling/rollback/canary/blue-green). Remaining: monitoring, security hardening, troubleshooting lab (Phases 13–17).
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

## Phase 12 — Deployment Strategies ✅ (complete)

Implement:
- Rolling updates via Floci ECS/EKS
- Blue/green via Floci CodeDeploy (traffic shifting)
- Canary via Floci CodeDeploy + ELB target groups
- Rollback via CodeDeploy auto-rollback
- Progressive delivery discussion

> **Complete ✅ (`6397127`)** — all four strategies demonstrated **live on Floci EKS (real k3s)** with measured results, and documented in `docs/deployment-strategies.md` with a reproducible `scripts/demo-deploy-strategies.sh` + `k8s/demo/` manifests:
> - **Rolling** — explicit chart strategy (RollingUpdate, maxSurge 1 / maxUnavailable 0): v2 upgrade across 3 replicas, incremental pod replacement, zero downtime.
> - **Rollback** — deliberately broken image → CrashLoopBackOff while old v2 pods stayed healthy → `kubectl rollout undo` restored 3/3; revision trail captured.
> - **Canary** — v3 canary sharing the Service by replica weight: 80 in-cluster requests → **38× v3 / 42× v2 (~50/50 at 3+3)**, then promoted + cleaned up.
> - **Blue/Green** — two full stacks + `imageflow-bg` Service: blue v2 live (20/20) → atomic selector flip → green v3 (20/20) → flip back (rollback).
> - **Floci caveat (honest):** CodeDeploy's lifecycle is *simulated* on Floci (no agent runs the appspec hooks), so real blue/green/canary traffic shifting via CodeDeploy is **not** demonstrable locally — the k3s demos are the genuine ones; the CodeDeploy config (incl. auto-rollback) remains real-AWS-correct.

Interview Topics: deployment failures, rollback strategy, release validation.

---

## Phase 13 — Monitoring & Observability ✅ (complete)

Master: metrics, logs, tracing, dashboards, alerting, SLI, SLO, error budgets.

Build:
- Application monitoring: Prometheus `/metrics` + Floci CloudWatch Metrics/Logs
- Infrastructure monitoring: Floci CloudWatch + OpenSearch (real engine)
- Alerting: CloudWatch Alarms → EventBridge / SNS
- Incident dashboards: OpenSearch + floci-ui

> **Complete ✅ (ADR-11)** — the CloudWatch-only stack is **live and probe-verified** against Floci:
> - **Prometheus `/metrics`** — now ships pipeline counters + histogram: `imageflow_uploads_total`, `imageflow_upload_errors_total`, `imageflow_upload_duration_seconds` (plus existing HTTP/uptime metrics).
> - **CloudWatch custom metrics** (namespace `ImageFlow`) — the API emits `Uploads`/`UploadErrors`; the Lambda emits `ProcessedCount`/`FailedCount` (`put_metric_data` verified: list-metrics + get-metric-statistics return datapoints).
> - **CloudWatch Logs** — optional `CloudWatchLogHandler` ships API log lines to `/imageflow/api` when `CLOUDWATCH_LOGS_ENABLED=true` (create-group/stream + put-log-events verified).
> - **Alerting** — Terraform `observability` module: alarms `imageflow-failed-images` + `imageflow-upload-errors` → SNS, plus EventBridge rule `imageflow-alarm-events` (alarm state changes → SNS). Floci stores alarm state but **not** `AlarmActions` (probe-verified) — alarms stay real-AWS-correct; the demonstrable alert path is EventBridge → SNS (persists).
> - **Observability script** — `scripts/observability.sh` (metrics + alarms + rules + logs + topics report) with deterministic behavior tests via a fake `aws` CLI.
> - Full write-up + demo runbook + SLI/SLO table: `docs/monitoring.md`. **OpenSearch deliberately excluded** (heavyweight real container; CloudWatch-only covers the story in-process — ADR-11).

Interview Topics: Golden Signals, RED, USE, MTTR.

---

## Phase 14 — Security ✅ (complete)

Master: identity, secrets, encryption, least privilege, supply chain security, image scanning, dependency scanning, policy enforcement, compliance.

Build:
- IAM roles/policies via Floci IAM + STS (real SigV4 auth)
- Secrets via Floci Secrets Manager + KMS
- Encryption via Floci KMS
- Cognito user pools via Floci Cognito
- WAF via Floci WAF v2; certificates via Floci ACM
- CI security gates: Trivy image scan, pip-audit, SAST

> **Complete ✅ (ADR-12)** — all security services probe-verified on Floci, provisioned by the Terraform `security` module, and demoed live:
> - **KMS** — key + alias (`alias/imageflow-app-key`); `security.sh kms` proves encrypt→decrypt round trip with opaque ciphertext.
> - **Secrets Manager** — `imageflow/app-secret` provisioned; `app/services/secrets.py` adds `fetch/put (upsert)/kms` helpers + **secrets-backed credential resolution** (`IMAGEFLOW_SECRET_NAME` → the app builds boto3 clients from secret-sourced creds; non-fatal fallback).
> - **Cognito** — pool + client + generated-password user; `security.sh cognito` runs the FULL flow live: admin-create → NEW_PASSWORD_REQUIRED challenge → respond → **real JWT claims** (iss/sub/exp/aud) decoded.
> - **WAF v2** — `imageflow-web-acl` with rate-limit (100/5min IP) + AWS-managed common rules; `security.sh waf` lists live rules.
> - **IAM** — `imageflow-reader` least-privilege user (one-bucket read-only policy); Lambda policy tightened (log-stream perms scoped to its log group). **Honest finding:** Floci validates SigV4 but does NOT enforce IAM authorization (probe-verified) — design real-AWS-correct, enforcement is a real-account control.
> - **Audit** — `scripts/security-audit.sh`: ripgrep secret scan (fails on findings — caught a literal fake key in a test fixture during dev) + IAM wildcard review. Behavior tests: 8.
> - **CI gates** — `security` job (pip-audit both reqs + gitleaks + trivy fs) + trivy image scan in build; runs under act.
> - Docs: `docs/security.md` (threat model → control map, demo runbook).

Interview Topics: security in CI/CD, secrets management, IAM design.

---

## Phase 15 — Reliability Engineering ✅ (complete)

Master: availability, scalability, resiliency, fault tolerance, disaster recovery, capacity planning.

Build (failure + recovery testing on Floci):
- Kill EC2 container, crash RDS, drain ECS tasks
- Recovery: Auto Scaling replacement, Lambda retries/DLQ
- Performance: load against local S3, DynamoDB, Lambda
- Chaos: stop containers, exhaust SQS, rotate IAM keys

> **Complete ✅ (ADR-13)** — `scripts/reliability.sh` drives the full reliability story **live on Floci** (17 behavior tests, fake aws + kubectl):
> - **Backup/restore drills** — `backup` exports `ImageFlowMetadata` **paginated** (JSON-lines, `--max-items`/`--starting-token`) + syncs `uploads/`/`thumbs/` → `data/backups/cloud-<ts>/` with a manifest; `restore` writes items back via `batch-write-item` (25/chunk, UnprocessedItems retries) + syncs S3 and **verifies counts against the manifest**; `drill` runs the full cycle (probe data → backup → simulated loss → restore → verify) and reports **measured RTO** (RPO=0 for the drill; production RPO = backup cadence).
> - **Failure injection** — `chaos kill-pod` (k3s pod delete → **Deployment controller self-heals**, recovery time measured) · `kill-instance` (ASG EC2 terminate → **Auto Scaling replacement** in ~9s) · `kill-api` (API process kill → `/health` fails → `deploy.sh` restart → healthy) · `fail-image` (corrupt upload → Lambda **FAILED dead-letter** → reset + fix the object → **replay the S3 event via `aws lambda invoke`** → PROCESSED — the real serverless retry path; the reset precedes the fix so the replay is the single deterministic retry — idempotent processing prevents double-counting, `ProcessedCount` verified at exactly 1).
> - **Auto-scaling reconciler** — `scaling` demonstrates the live k3s HPA + Deployment reconcilers AND the ASG instance count; `reconcile [--apply]` is the **explicit desired-vs-actual loop** over ASG + Deployment + HPA (dry-run by default; `--apply` runs `update-auto-scaling-group`/`kubectl scale`). Terraform `modules/autoscaling` provisions `imageflow-asg` (launch template `ami-test`/`t3.micro`, explicit AZs `us-east-1a/b`, min 1 / max 3 / desired 1).
> - **Honest Floci finding (refined by probe)** — `aws_launch_configuration` FAILS on Floci (create ok, describe empty → Terraform "empty result"), so the module uses a launch template; a launch-template-backed ASG **genuinely launches EC2 instances and reconciles replacements** (`chaos kill-instance`: terminated → replaced in ~9s, probe-verified; quirk: replacement stays `Pending` in the ASG view while EC2 says `running`). DynamoDB scan/batch-write, s3 sync, and lambda invoke (the backup/restore + retry paths) are fully live.
> - Docs: `docs/reliability.md` (RTO/RPO, chaos engineering, reconciler explainer, demo runbook).

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
