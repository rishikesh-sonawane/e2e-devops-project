# ImageFlow — Developer Guide

> The practical handbook for working in this repository — whether you're a new contributor, a future maintainer, or an interviewer trying to understand how the system is really built and operated. Everything here is **real and runnable on your own machine for $0**.

---

## 1. The big picture (60 seconds)

ImageFlow is an **event-driven image pipeline** wrapped in a complete DevOps platform. One upload → S3 + DynamoDB `PENDING` → S3 event notification → Lambda (Pillow) thumbnail + metadata → DynamoDB `PROCESSED` + SNS announcement. Around that core sits everything a production platform needs: Terraform IaC, a real k3s Kubernetes cluster via Helm, dual-loop CI/CD, observability, security, and reliability tooling.

**The local cloud is Floci** (MIT-licensed AWS emulator) at `http://localhost:4566`. All AWS calls — from the app, the scripts, Terraform, and the CLI — go to that endpoint with dummy credentials (`test`/`test`, region `us-east-1`). **Never rely on ambient real-cloud configuration** (AGENTS.md §2): every boto3 client and every script declares the endpoint explicitly.

---

## 2. Prerequisites

Install the full free toolchain (detailed guide: [setup.md](setup.md)):

| Tool | Why you need it |
|---|---|
| **Floci** | The local cloud — `floci start` + `eval $(floci env)` |
| **AWS CLI v2** | All `aws` commands against Floci |
| **Terraform** | Infrastructure as Code |
| **Docker Desktop** | Powers Floci's real-Docker services (Lambda, EKS, ECR, EC2) + local image builds |
| **kubectl + Helm** | The k3s cluster |
| **Python 3.12+** | The app + Lambda + tests |
| **shellcheck** | Shell linting (matches CI's pinned v0.11.0) |

One-time environment setup:

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt -r lambda/image-processor/requirements.txt
floci start
eval $(floci env)        # every new terminal that touches the cloud needs this
```

---

## 3. Repository map

```text
app/                         ImageFlow API (FastAPI, Python 3.12)
├── main.py                  App entrypoint: FastAPI, /health /version /metrics /config
├── config/settings.py       Env-driven settings (pydantic-settings), secrets masked
├── routes/images.py         Upload → S3 + DynamoDB; get/list with presigned URLs
└── services/                storage.py (S3) · metadata.py (DynamoDB) · secrets.py
                             (Secrets-Manager-backed creds) · observability.py (metrics)

lambda/image-processor/      The worker Lambda (standalone — imports nothing from app/)
├── handler.py               S3-event trigger → Pillow thumbnail + metadata → PROCESSED
└── Dockerfile               public.ecr.aws/lambda/python:3.12 + Pillow

terraform/                   Infrastructure as Code
├── modules/                 storage · database · messaging · compute ·
│                            observability · security · autoscaling
└── environments/dev/        Backend (Floci S3 + DynamoDB locking), provider, variables

helm/imageflow/              Kubernetes packaging (Deployment, Service, ConfigMap,
                             Secret, HPA, optional Ingress) — targets Floci EKS (k3s)

k8s/demo/                    Canary + blue/green manifests (Phase 12 demos)

scripts/                     Operational tooling (all shellcheck-clean, behavior-tested)
├── deploy.sh                Prereqs → terraform → start API (real listener pid) → smoke
├── health-check.sh          /health + Floci reachability
├── cleanup.sh               Confirmed teardown
├── backup.sh                Repo-state snapshot (tar)
├── push-lambda.sh / push-api.sh    Build + push images to Floci ECR
├── reliability.sh           backup/restore/drill/chaos/scaling/reconcile
├── observability.sh         CloudWatch metrics/alarms/rules/logs report
├── security.sh / security-audit.sh  Phase 14 demos + audit
├── setup-inner-loop.sh      Provisions CodePipeline→CodeBuild→CodeDeploy (idempotent)
├── process-pending.sh       Direct-mode trigger: scan PENDING → process via venv Python
├── demo-deploy-strategies.sh  Replays rolling/rollback/canary/blue-green on k3s
├── lint.sh                  shellcheck over every script (CI gate)
├── codedeploy/              appspec lifecycle hooks: validate · deploy · stop · start
└── tests/                   test_*.sh — behavior tests for the scripts

.github/workflows/           ci.yml (lint→test→build→security) · deploy.yml · release.yml
tests/                       Integration tests (Floci-backed, skip without Floci)
docs/                        All documentation
.ai_memory/                  AI session memory (system state, tasks, ADRs)
```

---

## 4. The developer loop

```bash
# 1. Cloud is up (every session)
floci start && eval $(floci env)

# 2. If infrastructure changed: rebuild the Lambda image FIRST (compute module
#    references its ECR URI), then apply Terraform
bash scripts/push-lambda.sh
terraform -chdir=terraform/environments/dev apply -auto-approve

# 3. Run the API
bash scripts/deploy.sh --skip-terraform --skip-smoke    # or: uvicorn app.main:app

# 4. Test your change
source .venv/bin/activate
pytest -q                                   # 54 tests (36 app + 17 lambda + 1 live integration)
ruff check app/ lambda/image-processor/     # style
bash scripts/lint.sh                        # shellcheck over all scripts
for t in scripts/tests/test_*.sh; do bash "$t"; done    # 59 behavior tests, 7 suites

# 5. Verify live
bash scripts/health-check.sh
curl -s -F "file=@photo.png" http://localhost:8000/api/v1/images   # → PENDING → PROCESSED
```

---

## 5. Testing — what runs where

| Suite | Command | Count | Needs cloud? |
|---|---|---|---|
| API unit tests | `pytest app/tests` | 36 | No (in-memory fakes) |
| Lambda tests | `pytest lambda/image-processor/tests` | 17 | No (fakes) |
| Live integration | `pytest tests` | 1 | Yes (Floci) — auto-skips otherwise |
| Script behavior tests | `bash scripts/tests/test_*.sh` | 59 across 7 suites | Mostly no (fake `aws`/`kubectl` on PATH; a few spin up real uvicorn) |
| Lint | `ruff` / `scripts/lint.sh` (shellcheck) / `terraform fmt -check` / `helm lint` | — | No |

**Convention:** unit tests are hermetic — they never touch the network. Live verification happens in the scripts' test suites or manually. If you add a feature, add a test in the matching suite; CI will run it on every push.

---

## 6. CI/CD — how the two loops work

### Outer loop — GitHub Actions (`.github/workflows/ci.yml`)

Runs on every push/PR to `main`:

1. **Lint & static checks** — ruff + shellcheck + terraform validate + helm lint
2. **Unit tests** — pytest (integration test skips: no Floci on the runner)
3. **Build Docker image** — multi-stage, non-root; then a **Trivy image scan** (HIGH/CRITICAL gate)
4. **Security gates** — pip-audit (dependency CVEs) + gitleaks (secrets in history) + Trivy filesystem scan

### Inner loop — Floci CodePipeline (the "AWS-native" pipeline)

Provisioned by `scripts/setup-inner-loop.sh` (idempotent):

```text
S3 source.zip → CodeBuild (runs the real buildspec.yml: ruff + pytest gates,
                then Kaniko daemonless image build + push to ECR)
             → CodeDeploy (on-premises deployment group, auto-rollback)
```

Trigger it:

```bash
python3 -c "import boto3; cp=boto3.client('codepipeline',endpoint_url='http://localhost:4566',region_name='us-east-1',aws_access_key_id='test',aws_secret_access_key='test'); print(cp.start_pipeline_execution(name='imageflow-pipeline')['pipelineExecutionId'])"
aws codepipeline get-pipeline-state --name imageflow-pipeline --query 'stageStates[].[stageName,latestExecution.status]' --output table
```

> **Known Floci quirks (documented, ADR-10/11/12/13):** CodeBuild has no Docker → Kaniko; CodeDeploy targets resolve via *on-premises* registration; the CodeDeploy lifecycle is simulated; Floci stores alarm state but not alarm actions; Floci validates SigV4 but doesn't enforce IAM authorization.

---

## 7. Conventions (read before committing)

- **Git:** GitHub Flow — `main` is sacred and always green; work on short-lived `feature/<slug>` branches; squash-merge via PR. Full rules: [source-control.md](source-control.md).
- **Commits:** Conventional Commits — `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `test:` + short imperative summary.
- **Identity:** every commit is authored by the repo owner (repo-local git config); agents never use `--author` (AGENTS.md §3.6).
- **Python:** ruff-clean, type-annotated signatures, `from __future__ import annotations`.
- **Shell:** shellcheck-clean (SC2015/SC2317/SC2329 conventions in tests), `set -euo pipefail`, exit codes 0/1/2 contract, `--help`.
- **Terraform:** modules over monolith, `terraform fmt` clean, lifecycle blocks documented when used for Floci quirks.
- **Secrets:** zero hardcoded secrets, ever. CI scans for them.
- **Docs:** every feature ships with documentation + an ADR when it's a significant decision.

---

## 8. Making a change — worked example

Say you want to add a `DELETE /api/v1/images/{id}` endpoint:

1. **Branch:** `git checkout -b feature/delete-image`
2. **Implement:** add the route in `app/routes/images.py`; add `delete_record` in `app/services/metadata.py` (it already exists for upload rollback — reuse it).
3. **Test:** extend `app/tests/test_images_api.py` with a delete test using the in-memory fakes; add a script-level check if the ops surface changes.
4. **Validate:** pytest + ruff + shellcheck + script suites (section 4).
5. **Live-verify:** upload, delete, confirm the record and object are gone.
6. **Document:** update the endpoint table in `docs/architecture.md` / `README.md` if user-facing; add an ADR only if it changes a significant decision.
7. **Ship:** push branch → open PR → CI must pass → squash-merge → delete branch.

---

## 9. Troubleshooting common gotchas

| Symptom | Cause → Fix |
|---|---|
| `botocore` errors / "connection refused" | Floci not up in this shell → `floci start && eval $(floci env)` |
| Lambda event fires but record stays `PENDING` | Upload race: the record must be written **before** the object (record-first is the fixed convention) |
| `chaos kill-api` says "API process not running" | API isn't running in that shell → `bash scripts/deploy.sh --skip-terraform --skip-smoke` first (deploy.sh now writes the *real* listener pid) |
| Helm upgrade ignores new `image.tag` | Stored release values override CLI defaults → pass explicitly: `helm upgrade ... --set image.tag=latest` |
| Pod ImagePullBackOff after `latest` retag | `imagePullPolicy` must be `Always` (chart default) or the node caches the old digest |
| `terraform plan` shows perpetual `~ update` | Floci normalization quirk → covered by documented `ignore_changes`; check the resource's lifecycle block before "fixing" it |
| Script tests fail only on GitHub CI | Tool-version skew (e.g., shellcheck) → CI pins the same versions as local (`v0.11.0`) |
| `/health` answers one more time after kill | uvicorn graceful SIGTERM window → the reliability script polls for failure rather than a single curl |

---

## 10. Contributing checklist (Definition of Done)

- [ ] Feature works live on Floci (not just unit tests)
- [ ] Tests added/updated in the right suite; full pytest + script suites green
- [ ] ruff + shellcheck + terraform fmt + helm lint clean
- [ ] Docs updated (README/architecture or the phase doc)
- [ ] ADR written if it's a significant decision
- [ ] Memory synced if you're working with the AI assistant (`.ai_memory/`, AGENTS.md §3)
- [ ] PR opened, CI green, squash-merged, branch deleted
