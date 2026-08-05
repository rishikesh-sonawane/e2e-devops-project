# ImageFlow — Manual Execution & Verification Runbook

> **Purpose:** a complete, ordered, copy-pasteable guide to run the whole ImageFlow
> system yourself and verify every layer by hand — no agent required. Each phase's
> output is the evidence for the next. All commands run from the **repo root**
> (`/Users/rishi/Code/e2e-devops-project`).
>
> Companion docs: [`docs/setup.md`](setup.md) (tooling) · [`docs/architecture.md`](architecture.md)
> · [`docs/roadmap.md`](roadmap.md) · phase write-ups: [`deployment-strategies.md`](deployment-strategies.md),
> [`monitoring.md`](monitoring.md), [`security.md`](security.md), [`reliability.md`](reliability.md).

---

## Phase 0 — Prerequisites (one-time)

```bash
# Tools — install anything missing (see docs/setup.md):
floci --version && aws --version && terraform version && docker version --format '{{.Server.Version}}'
kubectl version --client && helm version --short && python3.12 --version && shellcheck --version | head -1

# Virtualenv (needed for pytest, process-pending.sh, deploy.sh):
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt -r lambda/image-processor/requirements.txt
```

**Start the local cloud** — every terminal session that touches the cloud needs this:

```bash
floci start
eval $(floci env)        # exports AWS_ENDPOINT_URL=http://localhost:4566, creds test/test, region us-east-1
floci doctor             # all checks pass?
```

> ⚠️ **Gotcha:** background processes started in one shell die when that shell exits.
> Anything that must keep running (the API, `kubectl port-forward`) lives in a terminal
> you leave open.

---

## Phase 1 — Static validation (no cloud needed)

```bash
source .venv/bin/activate
pytest -q                          # expect: 53 passed (36 app + 17 lambda)
ruff check app/ lambda/image-processor/      # expect: All checks passed
bash scripts/lint.sh               # expect: shellcheck: all scripts clean
for t in scripts/tests/test_*.sh; do echo "== $t"; bash "$t" | tail -1; done   # 7 suites, all PASSED

terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev validate   # Success! The configuration is valid.
terraform -chdir=terraform/environments/dev fmt -check -recursive ../../   # exit 0 = formatted

helm lint helm/imageflow          # expect: 0 chart(s) failed
```

---

## Phase 2 — Cloud + infrastructure bring-up (order matters!)

```bash
eval $(floci env)

# 1) Lambda image FIRST — the terraform compute module references its ECR image URI:
bash scripts/push-lambda.sh        # build + push image-processor → Floci ECR :5100

# 2) IaC — S3 backend + DDB locking; provisions storage/database/messaging/compute +
#    observability/security/autoscaling modules:
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev apply -auto-approve
# Re-run shows "No changes" → the blueprint is idempotent (no drift).
```

**Verify the cloud inventory:**

```bash
aws s3 ls                                     # imageflow-uploads, -thumbs, -state, -logs
aws dynamodb list-tables                      # ImageFlowMetadata, TerraformLocks
aws sns list-topics                           # imageflow-events
aws lambda list-functions                     # image-processor
aws kms list-aliases                          # alias/imageflow-app-key
aws secretsmanager list-secrets               # imageflow/app-secret
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names imageflow-asg \
  --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[0].InstanceId]' --output text   # 1 + instance id
terraform -chdir=terraform/environments/dev state list   # full module inventory in state
```

---

## Phase 3 — Application + serverless pipeline (the core demo)

```bash
# Start the API (keep this terminal open):
bash scripts/deploy.sh            # prereqs → terraform (idempotent) → uvicorn → smoke test
# or, infra already applied:  bash scripts/deploy.sh --skip-terraform

# Verify the app is alive:
bash scripts/health-check.sh      # All services healthy. (exit 0)
curl -s http://127.0.0.1:8000/health     # {"status":"ok",...}
curl -s http://127.0.0.1:8000/version    # git SHA + build timestamp
curl -s http://127.0.0.1:8000/metrics    # Prometheus counters
curl -s http://127.0.0.1:8000/config     # settings, secrets masked as ***
```

**The money demo — upload → auto-process → retrieve:**

```bash
# Make a tiny real PNG (or use any .png):
python3 -c "import base64; open('/tmp/demo.png','wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))"

curl -s -F "file=@/tmp/demo.png" http://127.0.0.1:8000/api/v1/images    # {"image_id": "...", "status": "PENDING"}
# Use the returned image_id, then poll:
watch -n 2 "curl -s http://127.0.0.1:8000/api/v1/images/<image_id> | python3 -m json.tool"
# ~5 seconds later: PENDING → PROCESSED with thumbnail_key + metadata.
# The S3 event notification fired the Lambda automatically — no manual trigger.

# Cross-check the internals:
aws dynamodb get-item --table-name ImageFlowMetadata \
  --key "{\"image_id\":{\"S\":\"<image_id>\"}}" --query 'Item.status.S'
aws s3 ls --recursive s3://imageflow-thumbs/          # thumbnail object exists
curl -s http://127.0.0.1:8000/api/v1/images           # paginated list includes it
```

**The dead-letter demo (must FAIL visibly):**

```bash
printf 'this is not an image' > /tmp/junk.bin
curl -s -F "file=@/tmp/junk.bin" http://127.0.0.1:8000/api/v1/images
# Poll → status becomes FAILED with an error field (invalid image data).
# A visible dead letter, not silent breakage.
```

**Direct-mode fallback** (the alternate processing path, bypassing the S3 trigger):

```bash
bash scripts/process-pending.sh   # scans PENDING records → processes via venv Python
```

---

## Phase 4 — Kubernetes + Helm + deployment strategies

```bash
eval $(floci env)
kubectl get nodes                 # the k3s node (v1.34.1+k3s1) — a real cluster

bash scripts/push-api.sh          # push the API image to Floci ECR

helm upgrade --install imageflow helm/imageflow --namespace default --create-namespace
kubectl get pods -w               # pod Running (1/1 Ready)
kubectl get hpa imageflow         # metrics-server reports CPU (e.g. 7%/70%)
```

**Deployment strategies** — first build the versioned images (full recipe in
`docs/deployment-strategies.md` §"Build the versioned images first"):

```bash
docker build --build-arg GIT_SHA=v2 -t localhost:5100/imageflow-api:v2 . && docker push localhost:5100/imageflow-api:v2
docker build --build-arg GIT_SHA=v3 -t localhost:5100/imageflow-api:v3 . && docker push localhost:5100/imageflow-api:v3
# "broken" = FROM :latest with a CMD that exits after 2s (readiness never passes)

bash scripts/demo-deploy-strategies.sh all
#   rolling   → v2 upgrade with maxSurge 1 / maxUnavailable 0 — zero downtime
#   rollback  → broken image → CrashLoopBackOff → rollout undo → 3/3 on v2
#   canary    → v3 slice ~50/50 (measured IN-cluster; port-forward lies on Floci — see docs)
#   bluegreen → atomic Service selector flip 20/20 v2 ↔ 20/20 v3
```

---

## Phase 5 — Inner-loop CI/CD (CodePipeline → CodeBuild → CodeDeploy)

```bash
eval $(floci env)
bash scripts/setup-inner-loop.sh  # idempotent: source.zip, kaniko cache, CodeBuild, pipeline, CodeDeploy, EC2

# Trigger a real run:
python3 -c "import boto3; cp=boto3.client('codepipeline',endpoint_url='http://localhost:4566',region_name='us-east-1',aws_access_key_id='test',aws_secret_access_key='test'); print(cp.start_pipeline_execution(name='imageflow-pipeline')['pipelineExecutionId'])"

# Watch the stages:
aws codepipeline get-pipeline-state --name imageflow-pipeline \
  --query 'stageStates[].[stageName,latestExecution.status]' --output table
# Expect: Source Succeeded → Build Succeeded (ruff+pytest gates, Kaniko daemonless image) → Deploy Succeeded
```

---

## Phase 6 — Observability

```bash
# Do a few uploads first so the counters move, then:
bash scripts/observability.sh     # metrics + alarms (core) · rules/logs/topics (info)

# Manual probes:
aws cloudwatch get-metric-statistics --namespace ImageFlow --metric-name ProcessedCount \
  --period 300 --statistics Sum \
  --start-time "$(python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(minutes=15)).strftime("%Y-%m-%dT%H:%M:%SZ"))')" \
  --end-time "$(python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
aws cloudwatch describe-alarms --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
aws events list-rules --query 'Rules[].[Name,State]' --output table     # imageflow-alarm-events ENABLED
```

**Log shipping (optional flag):** restart the API with `CLOUDWATCH_LOGS_ENABLED=true`
(setting in `app/config/settings.py`), hit a few endpoints, then:

```bash
aws logs filter-log-events --log-group-name /imageflow/api --query 'events[0:3].[timestamp,message]'
```

---

## Phase 7 — Security

```bash
bash scripts/security.sh all
#   kms      → encrypt/decrypt round trip, opaque ciphertext
#   secrets  → write a generated token, masked read (stored keys only)
#   cognito  → full flow: admin-create → NEW_PASSWORD_REQUIRED → respond → REAL JWT claims decoded
#   waf      → web ACL rules (rate-limit + AWS-managed)
#   iam      → least-privilege policy (honest note: Floci validates SigV4, does not enforce authz)

bash scripts/security-audit.sh    # 1) ripgrep secret scan (0 findings = clean) 2) IAM wildcard review
```

---

## Phase 8 — Reliability (the Phase 15 kit)

```bash
bash scripts/reliability.sh backup          # → data/backups/cloud-<ts>/ + manifest
bash scripts/reliability.sh drill           # backup → simulated loss → restore → measured RTO + verify
bash scripts/reliability.sh chaos kill-pod       # Deployment controller recreates the pod (needs kubectl)
bash scripts/reliability.sh chaos kill-instance  # ASG replaces the terminated EC2 instance (~5–9s)
bash scripts/reliability.sh chaos fail-image     # corrupt → FAILED dead-letter → fix → replay → PROCESSED
bash scripts/reliability.sh scaling             # HPA + Deployment reconcilers + ASG count
bash scripts/reliability.sh reconcile           # drift report (dry-run)
bash scripts/reliability.sh reconcile --apply   # corrects drift

# kill-api needs a running API + its pid file (deploy.sh writes data/api.pid):
# NOTE: deploy.sh resolves the REAL listener pid (lsof/pgrep on the port) — a
# backgrounded `cd && nohup uvicorn` makes `$!` the wrapper pid on macOS, which
# broke kill-api with "API process N not running" (fixed in PR #4).
bash scripts/reliability.sh chaos kill-api      # kill → /health fails → restart via deploy.sh → recovered
```

---

## Phase 9 — GitHub CI (outer loop)

```bash
git push origin main
gh run list --branch main --limit 1 --json status,conclusion,workflowName \
  -q '.[] | "\(.workflowName): \(.status)/\(.conclusion)"'
# watch live:
gh run watch "$(gh run list --branch main --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
# Expect all 4 jobs green: Lint, Unit tests (53), Security gates (pip-audit/gitleaks/trivy), Build (+ trivy image)
```

---

## Phase 10 — Teardown

```bash
kill "$(cat data/api.pid)" 2>/dev/null           # stop the API
bash scripts/cleanup.sh --yes                    # terraform destroy + remove data/ artifacts
kubectl delete deploy imageflow 2>/dev/null      # uninstall the k8s stack (or helm uninstall imageflow)
floci stop                                       # stop the local cloud (full reset)
```

---

## The 60-second "everything is verified" checklist

1. `pytest -q` → **53 passed** · `bash scripts/lint.sh` clean · 59 script tests pass.
2. `terraform apply` → **No changes** · ASG shows 1 instance.
3. Upload a PNG → **PROCESSED in ~5s** with a thumbnail.
4. `bash scripts/observability.sh` → metric datapoints + alarms present.
5. `bash scripts/security.sh all` → JWT claims print.
6. `bash scripts/reliability.sh drill` → `RTO: Xs` · `chaos kill-instance` → `ASG reconciled`.
7. GitHub CI badge green on `main`.
