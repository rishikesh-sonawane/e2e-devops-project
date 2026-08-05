# ImageFlow — Architecture

> **A production-inspired architecture, explained from first principles.** This document takes you from *"what are we building?"* to *"how does every piece fit, why was it designed this way, and how would I defend it in an interview?"* — with honest notes on what's emulated locally vs. what would change on real AWS.

---

## 1. The system in one paragraph

**ImageFlow is an event-driven image-processing pipeline** — the DevOps "hello world" that happens to touch *every* discipline:

1. A user uploads an image through a **FastAPI** service.
2. The service stores the original in **S3** and writes a `PENDING` record to **DynamoDB**.
3. An **S3 event notification** triggers a **Lambda** function (a real Docker container running Pillow).
4. The Lambda extracts metadata, generates a thumbnail, updates the record to `PROCESSED`, and publishes to **SNS**.
5. The user retrieves the original + thumbnail via presigned URLs.

Around that deliberately simple core sits the *real* subject of the project — the platform layer: Terraform IaC, a real Kubernetes cluster (k3s via Floci EKS), dual-loop CI/CD, observability, security hardening, and reliability engineering. **The app is simple so the engineering around it can be deep.**

---

## 2. Why this architecture (the three core decisions)

### 2.1 Event-driven, not request-driven — because that's how real systems scale

The pipeline is **decoupled**: the upload path never calls the processor directly. S3 → Lambda is a fire-and-forget event. This means:

- The API stays fast (it doesn't wait for processing).
- The processor scales independently (Lambda containers spin up per event).
- Failure is visible and retryable (a `FAILED` record is a dead-letter, not a hung request).

**Interview answer:** *"The upload path and the processing path are decoupled by an event — that's the same pattern used for order processing, video transcoding, or anything where work happens asynchronously. It's why the system degrades gracefully under load."*

### 2.2 The app is thin, the platform is everything

ImageFlow's FastAPI service is intentionally minimal — a few routes, three service clients (S3, DynamoDB, SNS). The value of the repository is that this thin app is **operated like a production system**: blue/green deployments, chaos drills, metrics-driven autoscaling, secret rotation, dependency scanning. That's the exact ratio most real teams have — a simple business app inside a sophisticated platform.

### 2.3 Everything runs locally on Floci — real services, zero cost

**Floci** is an MIT-licensed AWS emulator at `localhost:4566`. Crucially, it doesn't *simulate* everything — for many services it runs **real programs in real Docker containers**:

| "Real" on Floci | Meaning |
|---|---|
| Lambda | A real Docker container executes our Python code |
| EKS | A **real k3s Kubernetes cluster** (control plane + node) |
| ECR | A real OCI registry — `docker push` / `docker pull` work |
| EC2 + ASG | Real containers launched as instances; the auto-scaling group genuinely replaces terminated instances |
| CodeBuild | Real buildspec execution in a container |
| CloudWatch, KMS, Cognito, WAF, etc. | In-process but API-faithful (SigV4 validation, real JWTs, real KMS round trips) |

The same SDKs, CLI, and Terraform provider work unchanged — **skills transfer 1:1 to real AWS, at $0 cost and zero blast radius.**

---

## 3. Architecture views

### 3.1 Logical view — the pipeline

```
┌────────────┐   POST /api/v1/images    ┌───────────────────────────────┐
│   Client   │ ───────────────────────▶ │         ImageFlow API         │
└────────────┘                          │  (FastAPI, Python 3.12)       │
        ▲                               │  routes/images.py             │
        │  metadata + presigned URLs    │  services: storage (S3) ·     │
        └─────────────────────────────── │  metadata (DDB) · secrets ·  │
                                        │  observability                │
                                        └──────────────┬────────────────┘
                                                       │ 1. put original in S3
                                                       │ 2. put_item (PENDING)
                                                       ▼
                                        ┌───────────────────────────────┐
                                        │  S3  imageflow-uploads        │
                                        │  event notification (prefix   │
                                        │  uploads/)                    │
                                        └──────────────┬────────────────┘
                                                       │ 3. S3 event → invoke
                                                       ▼
                                        ┌───────────────────────────────┐
                                        │  Lambda  image-processor      │
                                        │  (Pillow: thumbnail + meta)   │
                                        └──────────────┬────────────────┘
                                          4. thumb →    │ 5. update_item
                                          S3 (thumbs)   │   PROCESSED
                                                        ▼
                                        ┌───────────────────────────────┐
                                        │  DynamoDB  ImageFlowMetadata  │
                                        │  6. SNS publish               │
                                        │   imageflow-events            │
                                        └───────────────────────────────┘
```

### 3.2 Layered view — the platform

| Layer | Components | Ownership |
|---|---|---|
| **Presentation** | FastAPI routes: `/health /version /metrics /config`, `/api/v1/images*` | `app/routes/` |
| **Application services** | S3 client, DynamoDB client, secrets resolution, observability emitter | `app/services/` |
| **Serverless compute** | Lambda image-processor (custom image, S3-triggered) | `lambda/image-processor/` |
| **Data plane** | S3 (uploads/thumbs/state/artifacts) · DynamoDB (metadata + locks) · SNS | Terraform modules |
| **Control plane** | Terraform state/locking · CloudWatch alarms/rules · KMS · Secrets Manager · Cognito · WAF · IAM | Terraform modules |
| **Orchestration** | Helm chart → k3s Deployment/Service/ConfigMap/Secret/HPA · k8s demo manifests | `helm/`, `k8s/demo/` |
| **Delivery** | GitHub Actions (outer) · CodePipeline→CodeBuild(Kaniko)→CodeDeploy (inner) | workflows, buildspec, appspec |
| **Operations** | 18 shellcheck-clean scripts (incl. CodeDeploy hooks): deploy, health-check, backup, observability, security, reliability, cleanup, lint, push, setup, process-pending | `scripts/` |

### 3.3 Deployment view — one app, three homes

| Home | How | Why it matters |
|---|---|---|
| **Laptop (venv)** | `uvicorn app.main:app` | Fastest inner loop |
| **Kubernetes** | Helm chart → Floci EKS (real k3s); HPA 1–3 @70% CPU | Real orchestration, real deployment strategies |
| **CI/CD pipeline** | CodePipeline → CodeBuild (Kaniko) → CodeDeploy | The AWS-native assembly line, end-to-end `Succeeded` |

Same image, three delivery paths — each one a different interview story.

---

## 4. Component deep-dives

### 4.1 The API — `app/`

- **Upload flow (record-first, deliberately):** the route computes the deterministic S3 key (`storage.original_key`), writes the DynamoDB `PENDING` record **before** the object lands in S3. Why? The S3 event can fire within milliseconds of the put — if the record doesn't exist yet, the Lambda correctly skips it ("missing record") and the image is stuck `PENDING` forever. Record-first guarantees the event always finds its record. **And if the upload itself fails, the record is rolled back (`delete_record`)** — no zombie `PENDING` items. This ordering is a live-drill-proven fix, not theory.
- **Failure semantics:** any cloud failure → logged server-side, returned as `503 cloud unavailable` (never leak internals); error counters increment.
- **Security hygiene:** filename sanitization (`Path().name` strips `../`), 10 MiB size cap, secrets masked in `/config`, credentials sourced from Secrets Manager when `IMAGEFLOW_SECRET_NAME` is set.

### 4.2 The Lambda — `lambda/image-processor/`

A standalone, custom-image Lambda (imports nothing from `app/`): reads the original from S3, extracts metadata (format, dimensions, size, SHA-256), writes a 256px aspect-preserving thumbnail to S3, updates the record to `PROCESSED`, publishes `image.processed` to SNS. Failure → `FAILED` + `error` field (an observable dead-letter). Processing is idempotent — already-`PROCESSED` records are skipped — which makes event replays and retries safe.

**Trigger paths (configurable via `IMAGE_PROCESSING_TRIGGER`):** primary S3 event; fallback direct invocation (`scripts/process-pending.sh`, `reliability.sh chaos fail-image` replay path).

### 4.3 Infrastructure as Code — `terraform/`

Seven modules, one dev environment, **S3 remote state + DynamoDB locking on Floci** (the same professional pattern real teams use):

| Module | Provisions |
|---|---|
| `storage` | uploads + thumbs buckets, S3→Lambda notification |
| `database` | `ImageFlowMetadata` (PAY_PER_REQUEST) |
| `messaging` | `imageflow-events` SNS topic |
| `compute` | IAM role/policy, ECR repo, image-backed Lambda, log-group-scoped policy |
| `observability` | CloudWatch alarms (`imageflow-failed-images`, `imageflow-upload-errors`) + EventBridge→SNS rule |
| `security` | KMS key+alias, `imageflow/app-secret`, Cognito pool/client/user, WAF v2 ACL, least-privilege IAM user |
| `autoscaling` | Launch template + ASG (`imageflow-asg`, min 1/max 3/desired 1, explicit AZs) |

**Idempotency is verified, not assumed:** `terraform plan` reports *"No changes"* on every run. Where Floci doesn't persist certain attributes (alarm `datapoints_to_alarm`, Cognito pool defaults, IAM user tags), documented `ignore_changes` blocks keep the plan converged without masking real-AWS behavior.

### 4.4 Kubernetes — `helm/imageflow` + Floci EKS (real k3s)

The chart ships: Deployment (non-root uid 1000, liveness/readiness on `/health`, RollingUpdate maxSurge 1 / maxUnavailable 0), Service, ConfigMap + Secret (checksum-annotated for automatic rollouts), HPA (1–3 @70%), optional Ingress. Deployed on a genuine k3s cluster; uploads through the clustered API are auto-processed by the Lambda — cross-target integration (EKS → S3 → Lambda) verified live.

### 4.5 CI/CD — the dual loop

- **Outer (GitHub Actions):** quality (ruff, shellcheck, terraform validate, helm lint) → tests (54) → build (non-root image, trivy-scanned) → security gates (pip-audit, gitleaks, trivy fs). **Green on every push.**
- **Inner (Floci):** CodePipeline (S3 source) → CodeBuild (real buildspec: gates, then **Kaniko daemonless** image build → ECR) → CodeDeploy (on-premises group, auto-rollback). Execution status: **Succeeded**.

### 4.6 Observability — three planes

1. **Prometheus-format `/metrics`** — pipeline counters + upload-latency histogram.
2. **CloudWatch custom metrics** — API: `Uploads`/`UploadErrors`; Lambda: `ProcessedCount`/`FailedCount`.
3. **Alerts** — Terraform alarms → SNS, plus an EventBridge rule on alarm state changes (the demonstrable local path; Floci stores alarm state but not alarm actions — ADR-11).

### 4.7 Security — defense in depth

KMS encryption keys · Secrets Manager (the app can source AWS credentials from a secret) · Cognito (full auth flow, real JWT claims) · WAF v2 (rate-limit + managed rules) · least-privilege IAM (single-bucket read-only demo user; Lambda policy scoped to its log group) · CI gates (pip-audit, gitleaks, trivy). **Honest limit (ADR-12):** Floci validates SigV4 but doesn't enforce IAM authorization — the design is real-AWS-correct; enforcement is a real-account control.

### 4.8 Reliability — proven, not promised

`scripts/reliability.sh` (with 17 behavior tests): paginated DynamoDB backup + S3 sync + manifest · restore with `batch-write-item` retries and count verification · **DR drill with measured RTO/RPO** · chaos: `kill-pod` (Deployment self-heals), `kill-instance` (ASG replacement in ~7–9s — genuinely live via launch templates), `kill-api` (process restart), `fail-image` (dead-letter → fix → replay → `PROCESSED`) · `scaling` (HPA + Deployment + ASG reconcilers) · `reconcile [--apply]` (explicit desired-vs-actual loop).

---

## 5. Data model

### DynamoDB — `ImageFlowMetadata`

| Attribute | Type | Notes |
|---|---|---|
| `image_id` | S (partition key) | UUID |
| `filename` / `content_type` / `size` | S/S/N | Upload metadata |
| `status` | S | `PENDING` → `PROCESSED` \| `FAILED` |
| `original_key` / `thumbnail_key` | S | S3 keys |
| `metadata` | M | format, width, height, sha256 |
| `error` | S | Set when FAILED (dead-letter) |
| `uploaded_at` | S | ISO timestamp |

### S3

| Bucket | Prefix | Content |
|---|---|---|
| `imageflow-uploads` | `uploads/` | Originals (event notification on this prefix) |
| `imageflow-thumbs` | `thumbs/` | Thumbnails |
| `imageflow-state` | — | Terraform remote state |
| `imageflow-artifacts` | — | Pipeline source.zip + Kaniko toolchain |

---

## 6. Key design decisions (with ADRs)

| Decision | Why (one line) | Record |
|---|---|---|
| Floci over real AWS | $0, zero blast radius, real-Docker fidelity for the services that matter | ADR-01 |
| Event-driven (S3→Lambda) | Decoupled, scalable, observable failure | ADR-07 |
| Kaniko in CodeBuild | Floci's build container has no Docker daemon — the industry daemonless answer | ADR-10 (deviation log) |
| Launch templates over launch configurations | Launch configs don't persist on Floci; templates are modern AWS best practice anyway | ADR-13 |
| `ignore_changes` for Floci quirks | Keeps plans idempotent without hiding real-AWS behavior | ADR-11/12/13 |
| Record-before-object on upload | Kills the stuck-`PENDING` race the live drill found | PR #4 |
| `ignore_changes` documented everywhere | "No changes" is a *proven* property, not a claim | PR #4 |
| Secrets-backed credentials | `IMAGEFLOW_SECRET_NAME` → app resolves AWS creds from Secrets Manager (non-fatal fallback) | ADR-12 |

---

## 7. Honest limits (what's emulated vs. real)

| Capability | Local (Floci) | Real AWS |
|---|---|---|
| Lambda, EKS (k3s), ECR, EC2/ASG, CodeBuild | **Real containers** — genuinely run | Same (production-grade) |
| SigV4 signing | Validated | Enforced + authorized |
| IAM authorization | **Not enforced** (policy is a design/audit exercise) | Enforced |
| CodeDeploy lifecycle | Simulated (status Succeeded; appspec hooks not executed) | Real agents + hooks |
| CloudWatch alarm actions | Stored state only, no actions | Actions fire |
| WAF enforcement | ACL stored, rules listed; no real ALB in front | Enforced at edge |
| Scale | Machine resources | Unlimited |

**Why publish these?** Credibility. An emulator has limits; documenting them precisely — and designing real-AWS-correct anyway — is exactly what a senior engineer does when presenting local proofs.

---

## 8. Interview talking points (from this architecture)

- **"Explain your event-driven pipeline"** → upload → S3 event → Lambda → DynamoDB + SNS; why decoupling matters; how failure becomes observable (`FAILED` dead-letter).
- **"How do you deploy without downtime?"** → RollingUpdate maxSurge 1/maxUnavailable 0; canary measured in-cluster (and why `port-forward` lies on Floci — it pins to one pod).
- **"How would you handle a spike in uploads?"** → HPA on CPU (proven 1→3→1), ASG for instances, PAY_PER_REQUEST DynamoDB, async processing as the natural buffer.
- **"What happens when your Lambda fails?"** → `FAILED` dead-letter + error field → CloudWatch alarm → SNS; fix + replay the event (idempotent processing makes replays safe).
- **"How do you keep IaC honest?"** → Remote state + locking, idempotent plan verified, `ignore_changes` only where emulator quirks demand, ADRs recording every deviation.
- **"How is this different from a tutorial project?"** → It's a *system*: real k3s, real ASG replacement, real JWTs, measured RTO, 113 automated checks, a manual verification runbook, and honest documentation of every limit.

---

## 9. Related reading

- [README.md](../README.md) — the project overview and quick start
- [LICENSE](../LICENSE) — MIT
- [docs/DEVELOPER.md](DEVELOPER.md) — repo map, dev loop, testing, conventions
- [docs/roadmap.md](roadmap.md) — the 19-phase mastery roadmap
- [docs/manual-verification.md](manual-verification.md) — run and verify every layer by hand
- Phase write-ups: [deployment-strategies.md](deployment-strategies.md) · [monitoring.md](monitoring.md) · [security.md](security.md) · [reliability.md](reliability.md)
- [.ai_memory/architectural_decisions.md](../.ai_memory/architectural_decisions.md) — the full ADR log
