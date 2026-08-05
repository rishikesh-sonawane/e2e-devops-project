# Architectural Decisions (ADR)

## ADR 01: ImageFlow — Event-Driven Image Pipeline over ML-Based Analyzer
- **Status:** Accepted
- **Decision:** Build **ImageFlow**: upload image → S3 → Lambda `image-processor` (real Docker, Pillow: thumbnail + metadata) → DynamoDB + SNS. Processing is our own deterministic Python, not a managed ML API.
- **Context:** The earlier "Media Analyzer" idea relied on AWS Rekognition, which **Floci does not emulate** (only stub-level Textract/Transcribe/Bedrock Runtime). Real AWS would violate the zero-cost principle; fake responses would violate real-fidelity.
- **Consequences:** Maximizes the DevOps/cloud footprint (storage, serverless, event-driven architecture, NoSQL, messaging, IAM, observability) with minimal app code, and everything runs genuinely on Floci for $0.

## ADR 02: Floci over LocalStack (and over Real AWS)
- **Status:** Accepted
- **Decision:** Use Floci as the local AWS emulator. Never provision real AWS.
- **Context:** LocalStack Community requires an auth token and froze updates (March 2026). Floci is MIT-licensed, no auth token, ~24 ms startup, ~13 MiB idle, ~90 MB image, and runs **real Docker** for Lambda, RDS, EKS (k3s), ECS, EC2, ElastiCache, MSK, OpenSearch, CodeBuild, plus a real ECR registry.
- **Consequences:** All AWS SDKs/CLI/Terraform work unchanged against `http://localhost:4566` with dummy credentials.

## ADR 03: Floci Storage Mode Selection
- **Status:** Accepted
- **Decision:** Default `hybrid` (in-memory + async flush every 5s) for daily development; `memory` in CI; `persistent` when debugging data issues; `wal` for production-durability simulation.
- **Context:** Floci offers memory / persistent / hybrid / wal modes trading speed for durability.
- **Consequences:** State survives container restarts in dev without sacrificing much performance.

## ADR 04: Floci EKS (k3s) as Primary Orchestration Target — No Minikube/Kind
- **Status:** Accepted
- **Decision:** Use Floci EKS (a **real k3s cluster** with a live Kubernetes API server) as the local K8s target, deployed via Helm. Minikube/Kind are not installed.
- **Context:** Floci EKS provides real k3s, keeping one toolchain for the whole project and preserving zero-cost. kubectl and Helm still apply unchanged.
- **Consequences:** Helm charts and manifests verified against a genuine Kubernetes API server, locally and free.

## ADR 05: Dual-Loop CI/CD
- **Status:** Accepted
- **Decision:** Outer loop = GitHub Actions (lint, SAST, tests, build, push to Floci ECR, Terraform plan). Inner loop = Floci CodePipeline → CodeBuild (real buildspec) → CodeDeploy (rolling / blue-green / canary / auto-rollback).
- **Context:** Exercises both hosted CI (interview-relevant, free tier) and AWS-native CI services (CodePipeline/CodeBuild/CodeDeploy) without cost.
- **Consequences:** Two deployment paths to learn and compare; all local.

## ADR 06: Image-Backed Lambda with Pillow
- **Status:** Accepted
- **Decision:** Package the `image-processor` Lambda as a **custom Docker image** pushed to Floci ECR (public Lambda Python base + Pillow), rather than a ZIP with dependency layers.
- **Context:** Floci runs Lambda in real Docker and ECR is a real registry; image-backed functions are the cleanest way to carry Pillow and match modern AWS best practice.
- **Consequences:** Familiar container packaging; `docker build/push` flows exercised as part of the pipeline.

## ADR 07: Configurable Lambda Trigger Path
- **Status:** Accepted
- **Decision:** Support `IMAGE_PROCESSING_TRIGGER=s3|dynamodb|direct` — primary path is S3 event notification → Lambda; fallbacks are DynamoDB Streams → Lambda event source mapping, or direct boto3 invoke from the API.
- **Context:** Floci documents S3 event notifications and DynamoDB Streams → Lambda event source mapping, but wiring behavior can vary by version; a configurable path guarantees the pipeline always works locally.
- **Consequences:** Slightly more configuration surface; robust, honest engineering that survives Floci version changes.
- **Verified (2026-08-04, Floci 0.2.0 / server v1.5.34):** S3→Lambda delivery **fires automatically** (upload → PROCESSED in ~5s). Image-backed Lambda works (ECR on :5100; boto3 needs `Code={ImageUri=...}`). **CRITICAL gotcha: never set `AWS_ENDPOINT_URL` in the Lambda's env** — inside the container `localhost` is the container, not the host; Floci injects its own reachable endpoint, and overriding it breaks in-container connectivity. `direct` mode (`scripts/process-pending.sh`) remains the fallback.

## ADR 08: Freebuff as Primary Assistant — OpenCode Zen "Big Pickle" Occasional
- **Status:** Accepted
- **Decision:** Use **Freebuff** (freebuff.com) as the single continuous AI assistant for this repo. Optionally use **OpenCode** with the OpenCode Zen **Big Pickle** (`big-pickle`) model *between* sessions for independent review — never as a continuous second assistant.
- **Context:** Managing multiple AI assistants simultaneously (multi-provider configs, mixed contexts, divergent state) is error-prone and noisy. Freebuff alone covers the full loop (read `.ai_memory/` → work → sync memory). OpenCode Zen's Big Pickle is currently free (trial) and useful for occasional second opinions.
- **Consequences:** One source of truth for project state (`.ai_memory/` + `AGENTS.md`). OpenCode outputs must be synced back into `.ai_memory/` before they count as done. Free-trial models (Big Pickle) may collect session data — never paste real secrets into them.

## ADR 09: Continuous Sync + Session Journal for Crash-Safe AI Memory
- **Status:** Accepted
- **Decision:** AI assistants sync **continuously**, not only at session end: write work to disk immediately, update `active_task.md` per step, and append one line to `.ai_memory/session_log.md` per completed step. Sessions that die before a final sync (context limit, daily cap, crash) are recovered deterministically via `git status` / `git diff` + the session-log tail.
- **Context:** End-of-session-only sync has a single point of failure: if the session ends before the snippet is emitted and applied, `.ai_memory/` is stale and conversational context is lost. Work on disk is never lost — only the summary can be stale.
- **Consequences:** Slightly more per-step bookkeeping; the maximum loss is bounded to un-synced *intent* (e.g., "I was about to scaffold terraform/"). Recovery is deterministic, so memory is effectively crash-safe.

## ADR 11: CloudWatch-Only Observability — Non-Fatal Telemetry (Phase 13)
- **Status:** Accepted
- **Decision:** Phase 13 monitoring = **Prometheus `/metrics` + CloudWatch custom metrics + CloudWatch Logs + CloudWatch Alarms → EventBridge → SNS**. **OpenSearch is deliberately excluded.** Hard rule: every telemetry emission is **non-fatal** — a CloudWatch outage degrades observability, never image processing. The API owns ingestion metrics (`Uploads`/`UploadErrors`), the Lambda owns outcome metrics (`ProcessedCount`/`FailedCount`).
- **Context:** Floci provides CloudWatch (in-process) and OpenSearch (real heavyweight container). Probes proved put-metric-data / get-metric-statistics / describe-alarms / put-rule / put-targets / create-log-group / put-log-events all work. The app already had a Prometheus `/metrics` endpoint; Phase 13 extends it with pipeline counters + a latency histogram and mirrors the same facts into CloudWatch so they are queryable and alarmable.
- **Consequences:** Three planes (app metrics, CloudWatch metrics, CloudWatch logs) + alerting, all demonstrable locally for $0. OpenSearch + Grafana/Prometheus-server remain documented extensions, not requirements. **Floci findings logged:** ① metric alarms persist but `AlarmActions` do **not** (accepted, then absent from describe-alarms — probe-verified) → alarms stay real-AWS-correct, the demonstrable alert path is the EventBridge rule → SNS (persists); ② **CloudWatch Logs is a separate boto3 service** — `boto3.client("logs")`, NOT methods on the `cloudwatch` client (AttributeError bug caught during live verification); ③ a `logging.Handler` must flush via a **background daemon thread** (emit-only flushing starves idle processes — the API sat quiet and buffered logs forever).

## ADR 10: Daemonless Image Builds with Kaniko in CodeBuild (DEVIATION LOG)
- **Status:** Accepted (deviation from ADR-05's literal "docker build" wording — intent unchanged)
- **Decision:** The CodeBuild stage builds the API image **without a Docker daemon** using **Kaniko** (Google's daemonless builder), pushing to Floci ECR. The Kaniko executor binary is cached in `s3://imageflow-artifacts/tools/kaniko-executor` (the "build toolchain in object storage" pattern).
- **Context:** ADR-05 said "CodeBuild (real buildspec)" without specifying the build mechanism. The original plan assumed `docker build` — but a probe build inside Floci's CodeBuild container proved there is **no Docker socket, no Docker CLI, and no TCP daemon** available (Floci runs buildspecs in a plain `python:3.12` container). `docker build` fails with `docker: not found`. Kaniko is the industry-standard solution (used on GitLab CI without dind, locked-down AWS runners, Kubernetes-native builds): same Dockerfile, same layers, identical output image, no daemon required.
- **Why gcr.io?** Kaniko is a Google project; since v1.20+ it ships **no GitHub release binaries** (GitHub API shows `assets: []` for all recent tags). The only official distribution is the container image at `gcr.io/kaniko-project/executor`, from which the static executor binary is extracted once and cached in Floci S3.
- **Floci-specific gotchas found while making this work:**
  1. The CodeBuild source mount (`/codebuild/output/src/src`) is **deleted mid-build once Kaniko runs** — writing any file to the cwd afterward fails. Fix: stage everything into `/tmp/ctx` + `/tmp/out` and pass Kaniko a **`tar://` context** (dir-context loses the mount mid-build and errors on COPY stages).
  2. Kaniko's `--context dir://` fails with `failed to get fileinfo for <dir>/app`; `tar://` succeeds because Kaniko extracts it into its own workspace first.
  3. `executor --version` is not a valid flag (prints usage + exit 1); use `executor --help` or skip.
- **Consequences:** Identical OCI image produced and verified pushed to Floci ECR (`host.docker.internal:5100/imageflow-api@sha256:ff0337...`). Adds a one-time toolchain-caching step; adds a strong "daemonless builds" interview talking point. **Process note (user directive 2026-08-04): all such deviations from written plans must be logged here with cause + evidence from this point forward.**
- **Verified (2026-08-04, Floci 0.2.0):** Full inner loop is live — CodePipeline (S3 source) → CodeBuild (buildspec: ruff+pytest gates → Kaniko build+push) → CodeDeploy deployment group `imageflow-onprem`, end-to-end **Succeeded**. Two Floci CodeDeploy findings: (1) **Floci resolves deployment targets via on-premises instance registration + tags** (`register_on_premises_instance` + `add_tags_to_on_premises_instances`), NOT EC2 tag filters — an EC2-tag deployment group fails with `NoInstancesReachable`. (2) **Floci simulates the CodeDeploy lifecycle** — the deployment shows `Succeeded` but the appspec hooks do NOT execute on the instance (Floci's EC2 instances ship only python3, no docker or codedeploy-agent). The appspec + hooks are real-AWS-correct and ready for a real CodeDeploy agent, but locally the deploy stage is status-simulation. Registry convention: `host.docker.internal:5100/imageflow-api` everywhere (matches Phase 11 EKS).
