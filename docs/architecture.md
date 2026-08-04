# ImageFlow — Architecture

## 1. Project Overview

This repository is a production-inspired DevOps ecosystem built from scratch. It demonstrates end-to-end DevOps practices: application development, containerization, CI/CD, infrastructure as code, cloud provisioning, orchestration, deployment strategies, monitoring, security, reliability engineering, and GitOps — all running locally via [Floci](https://floci.io), a free MIT-licensed AWS emulator.

**The application** is **ImageFlow**: an event-driven image pipeline. Users upload images, which are stored in S3, processed by a real Docker-backed Lambda (thumbnail generation + metadata extraction in pure Python/Pillow), indexed in DynamoDB, and announced over SNS.

### Core Principles

- **Everything runs locally** — no cloud account, no auth tokens, no costs
- **Real Docker fidelity** — Lambda, RDS, EKS, EC2, ECS, ElastiCache, MSK, OpenSearch spin up real containers
- **Same SDKs & tools** — AWS CLI, boto3, Terraform, CDK all work unchanged against `http://localhost:4566`
- **Interview-driven** — every phase builds toward confident interview answers
- **Documentation-first** — architecture, runbooks, and troubleshooting guides live in the repo

---

## 2. Architecture at a Glance

```
┌───────────────────────────────────────────────────────────────────┐
│                      Local Development Machine                     │
│                                                                    │
│  ┌──────────────────┐         ┌────────────────────────────────┐   │
│  │  ImageFlow API    │         │        Floci (port 4566)       │   │
│  │  (FastAPI)        │         │  ┌──────────────────────────┐  │   │
│  │                   │         │  │   HTTP Router (Vert.x)    │  │   │
│  │  /health /version │         │  └──────┬───────────────────┘  │   │
│  │  /metrics /config │         │         │                      │   │
│  │  /api/v1/images   │         │  ┌──────┴───────────────────┐  │   │
│  └────────┬─────────┘         │  │  Stateless Services       │  │   │
│           │                    │  │  SQS, SNS, IAM, STS,      │  │   │
│           │ upload             │  │  KMS, Cognito, SSM,       │  │   │
│           ▼                    │  │  EventBridge, API GW,     │  │   │
│  ┌──────────────────┐         │  │  CloudWatch, Step Funcs   │  │   │
│  │  S3 event        │───────► │  └──────────────────────────┘  │   │
│  │  notification    │          │  ┌──────────────────────────┐  │   │
│  └──────────────────┘          │  │  Stateful Services        │  │   │
│                                │  │  S3, DynamoDB, Streams    │  │   │
│  ┌──────────────────┐         │  └──────────────────────────┘  │   │
│  │  IaC (Terraform)  │         │  ┌──────────────────────────┐  │   │
│  │  state in S3      │         │  │  Container Services      │  │   │
│  │  locking in DDB   │         │  │  Lambda  → real Docker   │  │   │
│  └──────────────────┘         │  │  EKS     → real k3s       │  │   │
│                                │  │  ECS     → real tasks     │  │   │
│  ┌──────────────────┐         │  │  ECR     → real registry  │  │   │
│  │  CI/CD (dual-loop)│         │  │  RDS/ElastiCache/MSK/OS  │  │   │
│  └──────────────────┘         │  └──────────────────────────┘  │   │
│  ┌──────────────────┐         └────────────────────────────────┘   │
│  │  floci-ui (:3000) │                ┌──────────────────────┐     │
│  └──────────────────┘                 │   Docker Engine      │     │
│  ┌──────────────────┐                 │  (all containers)    │     │
│  │  Observability    │                 └──────────────────────┘     │
│  └──────────────────┘                                                │
└───────────────────────────────────────────────────────────────────┘
```

---

## 3. System Components

### 3.1 ImageFlow API (Sample Application)

A REST API service built with FastAPI (Python 3.12) — the deployment target and the entry point of the pipeline.

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | Liveness probe — returns 200 |
| `/version` | GET | Version info — Git SHA, build timestamp |
| `/metrics` | GET | Prometheus-format metrics |
| `/config` | GET | Runtime configuration dump |
| `/api/v1/images` | POST | Upload an image (multipart) → S3 + DynamoDB `PENDING` record |
| `/api/v1/images/{id}` | GET | Metadata + pre-signed S3 URLs (original + thumbnail) |
| `/api/v1/images` | GET | List / query processed images (pagination) |

Environment configuration via env vars; secrets injected through Floci Secrets Manager or Kubernetes Secrets at deploy time.

### 3.2 Image Processor Lambda

A **real Docker-backed Lambda** (Floci runs Lambda in actual containers) that does the pipeline's work in deterministic Python:

1. Reads the uploaded image from S3 (bucket `imageflow-uploads`, `uploads/` prefix).
2. Extracts metadata: format, width, height, byte size, SHA-256.
3. Generates a 256px thumbnail using Pillow and stores it in S3 (bucket `imageflow-thumbs`, `thumbs/` prefix).
4. Updates the DynamoDB record: `status=PROCESSED` + metadata + thumbnail key.
5. Publishes a message of type `image.processed` to the SNS topic `imageflow-events`.

Packaged as a custom image pushed to Floci ECR (Pillow runs inside the image, so no dependency-layer tricks are needed).

**Trigger path (configurable):**
- **Primary:** S3 event notification → Lambda (classic event-driven serverless).
- **Fallback A:** DynamoDB Streams → Lambda event source mapping.
- **Fallback B:** direct `boto3` invocation from the API.

Selected via env var `IMAGE_PROCESSING_TRIGGER=s3|dynamodb|direct`. Fallbacks guarantee the pipeline always works locally regardless of Floci version wiring behavior.

### 3.3 Floci — Local AWS Control Plane

Floci runs as a Docker container (or native binary via `floci start`) on port 4566 and provides **69 AWS services**.

| Layer | Description | Examples |
|---|---|---|
| **HTTP Router** | JAX-RS / Vert.x request dispatch | Routes all API calls |
| **Stateless Services** | In-process handlers | SQS, SNS, IAM, STS, KMS, Cognito, EventBridge, API Gateway, CloudWatch, Secrets Manager, Step Functions, CodePipeline, CodeDeploy, WAF v2 |
| **Stateful Services** | In-process with storage backend | S3, DynamoDB, DynamoDB Streams |
| **Container Services** | Real Docker-backed execution | Lambda, RDS, EKS, ECS, EC2, ElastiCache, MSK, OpenSearch, Neptune, DocumentDB, CodeBuild |
| **Registry** | Real OCI-compatible registry | ECR — `docker push` / `docker pull`, image-backed Lambda |

**Key characteristics (verified from official docs):**
- Startup ~24 ms, idle memory ~13 MiB, image ~90 MB
- License: MIT — free forever, no auth token, no feature gates (LocalStack Community requires a token since March 2026)
- Auth: none required — any non-empty credentials work (12-digit keys enable multi-account isolation)

### 3.4 CI/CD Pipeline (Dual-Loop)

**Layer 1 — GitHub Actions (outer loop):**
- Triggered on push/PR to `main`
- Lint, format, type-check, unit tests
- SAST + dependency scanning + image scanning (Trivy)
- Build and push Docker images to Floci ECR
- Run Floci-backed integration tests
- Terraform plan validation

**Layer 2 — Floci CodePipeline (inner loop):**
- Local pipeline orchestration (in-process)
- CodeBuild for real `buildspec` execution (real Docker)
- CodeDeploy for deployment strategies: rolling, blue/green, canary, auto-rollback

### 3.5 Infrastructure as Code

Terraform / OpenTofu manages all infrastructure:

```text
terraform/
├── modules/
│   ├── storage/          # S3 buckets (uploads, thumbs, state, logs)
│   ├── database/         # DynamoDB table + Streams
│   ├── compute/          # Lambda function + triggers
│   ├── messaging/        # SNS topics + subscriptions
│   ├── networking/       # VPC, subnets, security groups
│   ├── iam/              # Roles, policies, instance profiles
│   └── orchestration/    # EKS (k3s) and ECS cluster definitions
├── environments/
│   ├── dev/              # Floci local development
│   └── ci/               # CI pipeline environment
└── backend.tf            # S3 remote state + DynamoDB locking via Floci
```

### 3.6 Container Orchestration

Two orchestration targets for learning:

**Floci EKS** — a real k3s cluster (live Kubernetes API server):
- Deployments, Services, Ingress
- ConfigMaps, Secrets
- Horizontal Pod Autoscaler
- Rolling updates
- Helm chart: `helm/imageflow`

**Floci ECS** — real container tasks:
- Task definitions, services, capacity providers
- Fargate-shaped (local) task execution

### 3.7 Monitoring & Observability

| Component | Tool | Source |
|---|---|---|
| Metrics | Floci CloudWatch Metrics | Application + infrastructure |
| Logs | Floci CloudWatch Logs | API stdout + Lambda + container logs |
| Search | Floci OpenSearch (real engine) | Log aggregation and dashboards |
| Alerts | Floci CloudWatch Alarms → EventBridge / SNS | Threshold-based alerting |
| Dashboard | floci-ui (`localhost:3000`) | Visual resource browser |
| App metrics | Prometheus-format `/metrics` | Upload count, processing latency, failure rate |

### 3.8 Security

| Service | Role |
|---|---|
| Floci IAM + STS | Users, roles, policies, instance profiles, SigV4 auth |
| Floci KMS | Encryption keys for S3 / DynamoDB |
| Floci Secrets Manager | Application secrets |
| Floci Cognito | User pools, JWT auth (optional phase) |
| Floci ACM | TLS certificates |
| Floci WAF v2 | Web ACLs, rate limiting |
| Floci CloudTrail | API activity logging |

---

## 4. Floci Integration Deep Dive

### 4.1 Starting Floci

**Preferred — native CLI:**
```bash
curl -fsSL https://floci.io/install.sh | sh
floci start
eval $(floci env)
```

**Alternative — Docker Compose:**
```yaml
# floci-compose.yml
services:
  floci:
    image: floci/floci:latest
    ports:
      - "4566:4566"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
    environment:
      - FLOCI_STORAGE_MODE=hybrid
      - FLOCI_HOSTNAME=floci
      - FLOCI_DEFAULT_REGION=us-east-1
```

### 4.2 Environment Configuration

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
```

### 4.3 Service Mapping (ImageFlow)

| Project Phase | AWS Service | Floci Implementation |
|---|---|---|
| 1 — App Foundation | API Gateway / FastAPI | In-process REST handler |
| 7 — Containerization | ECR | Real OCI registry, `docker push/pull`, image-backed Lambda |
| 8 — CI/CD | CodeBuild | Real Docker buildspec execution |
| 8 — CI/CD | CodePipeline | In-process pipeline orchestration |
| 8 — CI/CD | CodeDeploy | In-process with Lambda traffic shifting |
| 9 — IaC | S3 (state) | In-process storage backend |
| 9 — IaC | DynamoDB (locking) | In-process storage backend |
| 10 — Cloud Infra | S3, DynamoDB, Lambda, SNS | In-process storage + real Docker Lambda |
| 10 — Cloud Infra | EC2 | Real Linux containers, SSH, IMDS, UserData |
| 10 — Cloud Infra | ELB v2 | In-process ALB/NLB with Lambda targets |
| 10 — Cloud Infra | RDS | Real PostgreSQL/MySQL containers |
| 10 — Cloud Infra | ElastiCache | Real Valkey/Redis containers |
| 11 — Orchestration | EKS | Real k3s cluster (live K8s API server) |
| 11 — Orchestration | ECS | Real container tasks |
| 12 — Deploy Strategies | CodeDeploy | Traffic shifting, auto-rollback |
| 13 — Monitoring | CloudWatch Logs / Metrics | In-process ingestion + alarms |
| 13 — Monitoring | OpenSearch | Real OpenSearch engine |
| 14 — Security | IAM / KMS / Secrets Manager / Cognito / ACM / WAF v2 | In-process, SigV4 validation |
| 15 — Reliability | Backup | In-process simulated lifecycle |
| 16 — GitOps | EKS | k3s for ArgoCD/Flux targets |
| 17 — Troubleshooting | All | Simulate failures across services |

### 4.4 Storage Modes

| Mode | Behavior | Use |
|---|---|---|
| `memory` | Entirely in RAM | CI, ephemeral tests |
| `persistent` | Immediate flush to disk per write | Simple local state |
| `hybrid` | In-memory + periodic async flush (5s) | **Default for development** |
| `wal` | Write-ahead log before responding | Maximum durability |

### 4.5 Multi-Account Isolation

Floci supports per-account isolation via 12-digit `AWS_ACCESS_KEY_ID`:

```bash
AWS_ACCESS_KEY_ID=111111111111 aws s3 mb s3://prod-bucket
AWS_ACCESS_KEY_ID=222222222222 aws s3 mb s3://dev-bucket
# Resources are invisible across accounts
```

---

## 5. Repository Structure

```text
.
├── .ai_memory/                 # AI memory bank
├── .github/workflows/          # GitHub Actions CI/CD
├── app/                        # ImageFlow API
│   ├── main.py                 # FastAPI entry point
│   ├── routes/                 # API endpoints
│   ├── services/               # Business logic (S3, DynamoDB, SNS, Lambda clients)
│   ├── config/                 # Configuration + env parsing
│   ├── tests/                  # Unit tests
│   └── requirements.txt        # Pinned dependencies
├── lambda/
│   └── image-processor/        # Lambda source + Dockerfile (Pillow)
├── terraform/
│   ├── modules/                # Reusable Terraform modules
│   ├── environments/           # dev/ and ci/
│   └── backend.tf              # S3 + DynamoDB backend via Floci
├── helm/
│   └── imageflow/              # Helm chart (Deployment, Service, Ingress, ConfigMap, HPA)
├── scripts/                    # deploy.sh, health-check.sh, cleanup.sh, backup.sh
├── tests/                      # integration/ (Floci-backed), e2e/
├── docs/                       # architecture.md, roadmap.md, setup.md
├── docker-compose.yml          # Local development services
├── floci-compose.yml           # Floci local cloud
├── Makefile                    # Common commands
├── AGENTS.md                   # AI agent rules
└── README.md                   # Master vision
```

---

## 6. Development Workflow

```
                  ┌─────────────┐
                  │  Developer   │
                  └──────┬──────┘
                         │
                  ┌──────▼──────┐
                  │  Git Branch  │
                  │ (feature/*)  │
                  └──────┬──────┘
                         │
              ┌──────────▼──────────┐
              │  Local Development   │
              │  1. Start Floci      │
              │  2. Terraform apply  │
              │  3. Run ImageFlow    │
              │  4. Test endpoints   │
              └──────────┬──────────┘
                         │
                  ┌──────▼──────┐
                  │  Pull Request │
                  └──────┬──────┘
                         │
              ┌──────────▼──────────┐
              │  GitHub Actions CI  │
              │  - Lint & typecheck │
              │  - Unit tests       │
              │  - Build Docker img │
              │  - Push to ECR      │
              │  - Integration tests│
              │  - Terraform plan   │
              └──────────┬──────────┘
                         │
                  ┌──────▼──────┐
                  │  Merge → main │
                  └──────┬──────┘
                         │
              ┌──────────▼──────────┐
              │  Deployment Pipeline │
              │  - CodePipeline      │
              │  - CodeBuild image   │
              │  - CodeDeploy (BG/C) │
              │  - Smoke tests       │
              │  - Release tagging   │
              └──────────────────────┘
```

---

## 7. CI/CD Pipeline Architecture

### 7.1 GitHub Actions (Outer Loop)

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - lint, format, type-check
      - SAST + dependency scan + Trivy image scan
  test:
    runs-on: ubuntu-latest
    services:
      floci:
        image: floci/floci:latest
        ports: [4566:4566]
    steps:
      - unit tests
      - integration tests (Floci-backed)
  build:
    needs: [quality, test]
    steps:
      - build Docker image
      - push to Floci ECR
```

### 7.2 Floci CodePipeline (Inner Loop)

```
Source (Git) → CodeBuild (test) → CodeBuild (build)
    → CodeDeploy (beta) → Approval → CodeDeploy (prod)
```

### 7.3 Deployment Strategies

| Strategy | Implementation | Floci Service |
|---|---|---|
| **Rolling** | Incremental replacement of ECS/EKS tasks | ECS rolling update / k8s Deployment |
| **Blue/Green** | Two environments, swap traffic | CodeDeploy + ELB target groups |
| **Canary** | Percentage-based traffic shift | CodeDeploy + weighted ELB targets |
| **Rollback** | Automatic revert on failure | CodeDeploy auto-rollback |

---

## 8. Infrastructure Provisioning

### 8.1 Terraform Workflow

```bash
cd terraform
terraform init        # backend = Floci S3 + DynamoDB
terraform plan
terraform apply
terraform destroy
```

### 8.2 Provisioned Resources (ImageFlow)

```
S3 buckets
├── imageflow-uploads/          # Original images
├── imageflow-thumbs/           # Generated thumbnails
├── imageflow-state/            # Terraform remote state
└── imageflow-logs/             # CloudWatch log archive
DynamoDB
├── ImageFlowMetadata           # App table (status, metadata, keys) + Streams
└── TerraformLocks              # State locking
Lambda
└── image-processor             # Real Docker, Pillow, S3-triggered
SNS
└── imageflow-events            # image.processed topic
IAM
├── ImageFlowAPIRole            # S3, DynamoDB, SNS, Lambda invoke
├── ImageProcessorRole          # S3, DynamoDB, SNS, CloudWatch logs
└── CodeBuildRole               # ECR push, S3 artifacts
[Optional phases] VPC, ALB, EC2, RDS, ElastiCache, ECS, EKS, Cognito, WAF
```

---

## 9. Containerization Strategy

### 9.1 Multi-Stage Docker Build (API)

```
Stage 1: Build
  Base: python:3.12-slim
  Action: Install deps, run tests

Stage 2: Production
  Base: python:3.12-slim
  Action: Copy artifacts, set entrypoint
  User: non-root
  Health: HEALTHCHECK /health
  Label: git-sha, build-timestamp
```

### 9.2 Lambda Image (image-processor)

Built from the public Lambda Python base image (`public.ecr.aws/lambda/python:3.12`), `pip install Pillow`, packaged and pushed to **Floci ECR**, then registered as an image-backed Lambda function.

### 9.3 Image Registry (Floci ECR)

```bash
aws ecr create-repository --repository-name imageflow-api
docker build -t imageflow-api .
docker tag imageflow-api localhost:4566/imageflow-api:latest
docker push localhost:4566/imageflow-api:latest
```

---

## 10. Security Architecture

### 10.1 IAM Design

```text
AWS Account (000000000000 via Floci)
├── IAM Roles
│   ├── ImageFlowAPIRole (apigateway.amazonaws.com / ecs-tasks / pod identity)
│   │   └── S3 read/write (uploads, thumbs), DynamoDB CRUD, SNS Publish, Lambda Invoke
│   ├── ImageProcessorRole (lambda.amazonaws.com)
│   │   └── S3 read/write, DynamoDB Update, SNS Publish, CloudWatch Logs
│   ├── EKSRole (eks.amazonaws.com)
│   │   └── EKS policies, ECR Pull
│   └── CodeBuildRole (codebuild.amazonaws.com)
│       └── ECR Push, S3 ReadWrite
└── IAM Users
    └── developer (programmatic access, MFA)
```

### 10.2 Secrets Flow

```text
Application Launch
    │
    ▼
Floci Secrets Manager ←── KMS (encryption)
    │
    ▼
Application reads secret at startup (cached, periodic refresh)
    │
    ▼
Used as env vars or file mounts
```

---

## 11. Technical Decisions & Trade-offs

### 11.1 Why Floci vs Real AWS

| Factor | Floci | Real AWS |
|---|---|---|
| Cost | $0 | Pay-as-you-go |
| Speed | 24 ms startup | N/A (remote) |
| Fidelity | Real containers for key services | Production-grade |
| Blast radius | None — local container reset | Can cost money |
| Auth | Any non-empty credentials | Real IAM + keys |
| Service count | 69 | 200+ |
| Scale testing | Limited to machine resources | Unlimited |

### 11.2 Why Floci vs LocalStack

| Factor | Floci | LocalStack Community |
|---|---|---|
| License | MIT | Restricted |
| Auth token | None (required by LocalStack since March 2026) | Required |
| Startup | ~24 ms | ~3.3 s |
| Idle memory | ~13 MiB | ~143 MiB |
| Image size | ~90 MB | ~1.0 GB |
| Real Docker | Lambda, RDS, EKS, EC2, ECS, MSK, OpenSearch | Limited |
| Updates | Active | Frozen |

### 11.3 Storage Mode Selection Guide

| Scenario | Mode | Rationale |
|---|---|---|
| CI test run | `memory` | Fastest, no persistence needed |
| Daily development | `hybrid` | State survives restarts, minimal overhead |
| Debugging data issue | `persistent` | Immediate writes, inspect state on disk |
| Production simulation | `wal` | Maximum durability, crash recovery |

---

## 12. Interview Preparation Context

Each architecture decision maps to interview topics:

- **"Why Floci instead of real AWS?"** → Cost, speed, safety, trade-off discussion
- **"Explain your event-driven pipeline"** → S3 events → Lambda → DynamoDB → SNS; why async decoupling matters
- **"How does your Lambda run?"** → Real Docker containers; custom images via ECR; warm pool
- **"How would you design a VPC?"** → Subnets, route tables, IGW, NAT — provisioned via Terraform against Floci
- **"Explain blue/green deployment"** → Two CodeDeploy groups, ELB traffic swap — demonstrated locally
- **"How do you handle secrets?"** → Floci Secrets Manager + KMS encryption — same API as AWS
- **"What's your CI/CD pipeline?"** → GitHub Actions + Floci CodePipeline/CodeBuild/CodeDeploy
- **"How do you monitor applications?"** → Prometheus `/metrics` + CloudWatch Metrics/Logs + OpenSearch dashboards
- **"How do you handle IAM?"** → Users, roles, policies, instance profiles, STS — all via Floci
- **"What happens when your Lambda fails?"** → DLQ / retries, CloudWatch alarms, SNS alerting, runbook

---

## 13. Quick Start

```bash
# Start Floci
floci start            # or: docker compose -f floci-compose.yml up -d
eval $(floci env)

# Verify
aws s3 mb s3://imageflow-check

# Provision infrastructure
cd terraform
terraform init
terraform apply

# Run the application
cd ../app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```
