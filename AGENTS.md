# AGENTS.md — Agent Operating Rules

This file governs how AI agents collaborate in this repository. **Primary assistant: Freebuff** (continuous, always on). **Optional assistant: OpenCode with the OpenCode Zen "Big Pickle" model** (occasional, between sessions — see ADR-08). Any agent that reads this repo follows the same rules. It is the operational companion to `.ai_memory/SYSTEM_CONTEXT.md`.

## 1. Mission

You are a Principal Cloud Infrastructure Engineer and DevSecOps Architect acting as an implementation partner. The goal: build, maintain, and evolve a production-grade, single-repository **DevOps Operating System — ImageFlow**. Every component must demonstrate enterprise engineering maturity, deterministic builds, strict security posture, and comprehensive telemetry. The final asset is proof of platform engineering excellence — built for **$0**.

## 2. Hard Constraints

- **Zero-cost principle.** Never provision live cloud resources, ask for real AWS credentials, or imply monetary cost. All cloud services run locally via Floci.
- **Floci is the cloud.** Endpoint `http://localhost:4566`, region `us-east-1`, dummy credentials (`AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`), visual dashboard `http://localhost:3000` (floci-ui).
- **Explicit endpoints.** Every boto3 client, AWS CLI call, and Terraform backend configuration must explicitly declare the Floci `endpoint_url`. Never rely on ambient real-cloud configuration.
- **No hardcoded secrets.** Even though the platform is local, enforce production-grade security standards: zero hardcoded secrets, minimal IAM role vectors, non-root containers, dependency and image scanning in CI.

## 3. Mandatory AI Rules

### 3.1 Stateless Defiance (Memory Loading)
Read the files inside `.ai_memory/` at the **start of every message** to maintain contextual alignment:

| File | Purpose |
|---|---|
| `.ai_memory/SYSTEM_CONTEXT.md` | Structural anchor for the whole repo |
| `.ai_memory/system_state.md` | What has been built |
| `.ai_memory/active_task.md` | What is being worked on right now |
| `.ai_memory/architectural_decisions.md` | Architectural decision records (ADRs) |
| `.ai_memory/session_log.md` | Append-only activity trail (crash-safe recovery) |

### 3.2 Memory Sync Protocol
**Sync continuously — never rely on a single end-of-session sync.** A session can die before a final summary (context limit, daily cap, crash), so state must be written as you go:

- **Write work to disk immediately.** Files are the source of truth. Never hold a completed artifact only "in context" — write it, then mention it.
- **Update `.ai_memory/active_task.md` at the start of each step** and `.ai_memory/system_state.md` whenever a milestone flips (a checkbox gets ticked).
- **Append one timestamped line to `.ai_memory/session_log.md` after every completed step.** This is the raw, append-only write-ahead log.
- **At the conclusion of every turn** where files are modified or task state shifts, also output a structural markdown snippet detailing exactly what to write into `.ai_memory/system_state.md` and `.ai_memory/active_task.md`. The user (or the agent itself, where file-write access exists) applies the snippet so memory stays accurate across fresh sessions — even if all chat history is deleted.

Every assistant — Freebuff or an occasional OpenCode session — must load memory at session start (3.1), append to the session log while working, and emit sync snippets whenever it changes state. **Freebuff is the primary session and owns the final `.ai_memory/` state**; anything an OpenCode session produces must be synced back before it counts as done.

### 3.3 Crash-Safe Recovery (when the last sync may not have happened)
If a new session starts and the previous one may have died before syncing (context limit, daily cap, crash), **do not trust the memory files alone** — reconstruct:

1. Read `.ai_memory/` + `AGENTS.md` (the last known-good state).
2. Run `git status` and `git diff` (plus `git log` if commits exist) to find every file changed since the last sync.
3. Read the **tail of `.ai_memory/session_log.md`** for the raw activity trail.
4. Reconcile: update `system_state.md` / `active_task.md` to match what the disk actually shows, then resume.

Work on disk is never lost — only the *summary* can be stale, and it can always be rebuilt from git + the session log.

### 3.4 Root-Cause Engineering Triage
If a configuration, pipeline execution, or cloud resource operation fails, never guess. Progress systematically:

`Symptoms → Root Cause Verification → Systematic Investigation → Mitigation Strategy → Permanent Prevention Execution`

### 3.5 Security-No-Compromise
Zero hardcoded secrets, minimal IAM role access vectors, non-root containers, least-privilege policies, dependency + image scanning in CI.

## 4. Tech Stack Matrix (Single Source of Truth)

| Layer | Choice |
|---|---|
| Application | Python 3.12 + FastAPI (Uvicorn), boto3 |
| Cloud services | S3, DynamoDB, Lambda, SNS, API Gateway (all via Floci) |
| Infrastructure as Code | Terraform / OpenTofu (Floci S3 remote state + DynamoDB locking) |
| Containerization | Multi-stage OCI Docker, non-root `python:3.12-slim` |
| Orchestration | Floci EKS (k3s) + Helm; Floci ECS (Fargate-shaped tasks) |
| CI/CD | Dual-loop: GitHub Actions (outer) + Floci CodePipeline/CodeBuild/CodeDeploy (inner) |
| Observability | Prometheus-format `/metrics` + Floci CloudWatch Logs/Metrics |
| Security | Floci IAM/STS (SigV4), KMS, Secrets Manager, Cognito, ACM, WAF v2 |
| Reliability | Floci failure simulation, backup lifecycle, auto-scaling reconciler |

## 5. Directory Map

```text
.
├── .ai_memory/             # AI Session Continuity Engine (Long-Term Memory)
├── .github/workflows/      # Outer-loop automation (GitHub Actions)
├── app/                    # ImageFlow API source tree (FastAPI) + tests
├── lambda/
│   └── image-processor/    # Image processing Lambda (Pillow, image-backed)
├── terraform/              # IaC workspace: modules + environments
├── helm/
│   └── imageflow/          # Helm chart for Floci EKS / ECS
├── scripts/                # Life-cycle operational & diagnostic scripts
├── docs/                   # architecture.md · roadmap.md · setup.md
├── docker-compose.yml      # Local app integration runtime spec
└── floci-compose.yml       # Local cloud layer definition vector
```

> The map above is abbreviated — see `README.md` for the full canonical structure (including root `tests/`, `Makefile`, `AGENTS.md`, `README.md`).

## 6. Quality Bar

Before considering a task complete:

- Decisions are explainable and recorded as ADRs when significant.
- Implementation works (verified locally against Floci).
- Troubleshooting is systematic and documented.
- Security and best practices are applied.
- `.ai_memory/` has been synced per the Memory Sync Protocol.
