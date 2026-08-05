# ImageFlow Reliability Engineering (Phase 15)

> **Goal:** prove availability, scalability, resiliency, fault tolerance, and
> disaster recovery on the local cloud — for $0 on Floci. This phase turns the
> "it works" pipeline into a "**it survives**" pipeline: measurable backup/restore
> drills, deliberate failure injection with recovery, and an explicit
> **auto-scaling reconciler** (the desired-vs-actual control loop that runs
> the whole system).
>
> Everything is reproducible with one script:
> `scripts/reliability.sh` (commands: `backup` `restore` `drill` `chaos`
> `scaling` `reconcile` `all`). Behavior tests: `scripts/tests/test_reliability.sh`
> (17 checks, fake aws + kubectl). Terraform: `modules/autoscaling` (ADR-13).

---

## 1. Concepts — RTO, RPO, and the Reconciler

Three ideas anchor everything in this phase:

| Term | Meaning | How ImageFlow measures it |
|---|---|---|
| **RPO** (Recovery Point Objective) | How much data you're willing to lose. The gap between the last good backup and the disaster. | Backup cadence. The drill reports RPO=0 because the backup immediately precedes the simulated loss; production RPO = your scheduled backup interval. |
| **RTO** (Recovery Time Objective) | How long recovery takes. Time from disaster to "serving again". | Measured live: the drill timestamps restore start→end and reports seconds. |
| **Reconciler** | A control loop: read **desired state**, observe **actual state**, compute **drift**, **act** to correct it, verify. Runs continuously. | k3s Deployment controller, HPA, and the ASG are all reconcilers. `reliability.sh reconcile` implements the same loop explicitly, so the pattern is visible and testable. |

The reconciler loop is the *universal* reliability pattern — Kubernetes
controllers, Auto Scaling groups, and ArgoCD/Flux all run some version of:

```
DESIRED ──▶ observe ──▶ DIFF ──▶ ACT ──▶ verify ──▶ (loop)
   ▲                                              │
   └────────────── repeat forever ◀────────────────┘
```

## 2. What Was Built

### 2.1 Backup / Restore / Drill (`reliability.sh backup|restore|drill`)

The **data plane** backup (distinct from `backup.sh`, which snapshots repo
*state*): this one snapshots the *cloud data*.

- **DynamoDB** — the `ImageFlowMetadata` table is exported as JSON-lines,
  **paginated** with `--max-items`/`--starting-token` so the export is correct
  for large tables, not just the 66-item dev table (real-AWS-correct).
- **S3** — `uploads/` and `thumbs/` buckets are synced to the backup dir.
- A `manifest.txt` records item/object counts for restore verification.
- **`drill`** runs the full cycle: create probe data → backup → **simulated
  disaster** (delete the record + object) → restore → verify both are back →
  report measured **RTO** (and RPO=0 for the drill). Failure to restore fails
  the drill — this is a real recovery test, not a demo that always passes.

Restore writes items back with `batch-write-item` (25/chunk, retries
`UnprocessedItems` — the AWS-correct bulk-write pattern).

### 2.2 Failure Injection (`reliability.sh chaos <target>`)

Deliberate, observable failures with recovery — the essence of chaos
engineering (break it on purpose, in a controlled way, and *prove* the system
recovers):

| Target | Failure injected | Recovery mechanism verified |
|---|---|---|
| `kill-pod` | `kubectl delete pod` on the imageflow Deployment (k3s) | **Deployment controller** recreates the pod; recovery time measured (`rollout status`) |
| `kill-instance` | `ec2 terminate-instances` on the ASG's instance | **Auto Scaling group** launches a replacement (measured ~9s live on Floci) |
| `kill-api` | `kill` the host uvicorn process | `/health` fails → `deploy.sh` restarts it → `/health` OK again (process resilience) |
| `fail-image` | Upload **corrupt bytes** → Lambda marks the record `FAILED` (observable dead-letter) | Reset to PENDING → fix the object with valid bytes → re-inject the S3 event via `aws lambda invoke` → `PROCESSED` (retry/recovery path). Processing is idempotent, so the fix-upload's own S3 re-trigger and the replay can't double-count (`ProcessedCount` verified at exactly 1) |

`fail-image` is the most instructive: it proves the Lambda's FAILED state is a
real dead-letter (visible + queryable), and that a failed record can be
recovered by fixing the payload and replaying the event — exactly the AWS
serverless retry story. The reset happens **before** the fix upload so the
replay invoke is the single deterministic retry; if the fix upload's own S3
event also reprocesses first, the invoke lands on a `PROCESSED` record and is
skipped (idempotent), so exactly one reprocess happens.

### 2.3 Auto-Scaling Reconciler (`reliability.sh scaling` + `reconcile`)

Two layers:

1. **`scaling`** — demonstrates the live reconcilers: the k3s **HPA** (min/max
   replica bounds) and the **Deployment controller** (scaling to N replicas,
   `rollout status` until converged). On Floci these are *genuinely live*
   (Phase 11/12 verified: real k3s, metrics-server reporting `7%/70%`).
2. **`reconcile`** — the **explicit reconciler loop** over managed targets:
   - **ASG** `imageflow-asg`: desired capacity vs actual instance count.
   - **Deployment** `imageflow`: desired replicas vs ready replicas.
   - **HPA** `imageflow`: min/max vs current replicas.
   Reports drift per target; `--apply` executes the corrective action
   (`update-auto-scaling-group` / `kubectl scale`). Dry-run by default.

### 2.4 Terraform — `modules/autoscaling`

IaC for the scaling story: a launch template (`ami-test`, `t3.micro`) +
an Auto Scaling group (`imageflow-asg`, min 1 / max 3 / desired 1) with
`Project`/`Environment` tags, `health_check_type = "EC2"`, force-delete for
clean teardown, and **explicit availability zones** (`us-east-1a/b` — required
on real AWS, which no longer has EC2-Classic; Floci honours them and still
launches/reconciles instances, probe-verified). (Launch *configurations* fail
on Floci — see §3.)

## 3. Honest Floci Findings (ADR-13)

Probe-verified on Floci 0.2.0 / server 1.5.34:

1. **The ASG is a genuinely live reconciler — but only when backed by a
   launch template.** `aws_launch_configuration` resources fail on Floci
   (create returns success but `describe-launch-configurations` returns empty,
   so Terraform's post-create lookup errors with "empty result"). Launch
   templates DO persist, and an ASG backed by one **launches real EC2
   instances and reconciles replacements**: terminate the ASG's instance and
   a new one is created (`chaos kill-instance` reproduces it live in ~9s;
   probe-verified `i-…a233` → `i-…4c1c`). One quirk: the replacement stays
   `Pending` in the ASG's own view while the EC2 instance reports `running`.
   The k3s Deployment controller + HPA remain the other live reconcilers
   (Phase 11/12).
2. **The data-plane drill is fully live:** DynamoDB scan pagination,
   `batch-write-item` (with `UnprocessedItems` retries), `s3 sync` both
   directions, and `aws lambda invoke` all work against Floci — backup,
   restore, and the Lambda retry path are real, not simulated.
3. **Chaos on k3s is real:** deleting a pod genuinely exercises the Deployment
   controller (new pod scheduled + ready), and killing the API process
   genuinely requires a restart. One subtlety surfaced by the drill: uvicorn's
   graceful SIGTERM shutdown can still answer one more `/health` — the script
   polls for the failure rather than trusting a single curl.
4. **Explicit AZs are honoured:** the ASG now declares `us-east-1a/b`
   (real-AWS-correct — no EC2-Classic), and Floci still launches instances and
   reconciles replacements (`kill-instance` re-verified in ~5s after the
   change).

## 4. Demo Runbook

```bash
# Prereqs: floci running, terraform applied (incl. the autoscaling module),
# kubectl configured (eval $(floci env)), API deployed (helm) or host API up.

# 1. Full reliability pass:
./scripts/reliability.sh all          # backup → drill → chaos kill-api → scaling → reconcile

# 2. Individual pieces:
./scripts/reliability.sh backup       # snapshot data plane → data/backups/cloud-<ts>/
./scripts/reliability.sh restore      # restore newest backup
./scripts/reliability.sh drill        # full DR drill with measured RTO
./scripts/reliability.sh chaos kill-pod       # pod self-healing
./scripts/reliability.sh chaos kill-instance   # ASG Auto Scaling replacement
./scripts/reliability.sh chaos kill-api        # process restart
./scripts/reliability.sh chaos fail-image      # dead-letter → fix → reprocess
./scripts/reliability.sh scaling           # HPA + Deployment reconcilers
./scripts/reliability.sh reconcile         # drift report
./scripts/reliability.sh reconcile --apply # correct drift
```

### Expected outputs (live on Floci)

- `backup`: `backup complete (N items, U+T objects)` + manifest counts.
- `drill`: `RTO (measured restore time): Xs` + `RPO (drill): 0s` +
  `verification: metadata record + object restored and readable`.
- `chaos kill-pod`: `Deployment reconciler recreated the pod — recovery in Xs`.
- `chaos kill-instance`: `ASG reconciled: i-… → i-… in Xs`.
- `chaos fail-image`: `✓ FAILED observed — dead-letter works` then
  `✓ reprocessed to PROCESSED — retry/recovery path verified`.
- `reconcile`: per-target `desired=… actual=… → converged.` or `→ DRIFT
  detected.`; with `--apply`, `→ applied.`

## 5. Interview Talking Points

- **RTO/RPO**: define both; explain the trade-off (smaller RPO = more frequent
  backups = more cost) and how the drill *measures* recovery instead of
  assuming it.
- **Chaos engineering**: controlled, observable failure injection; the
  fail-image dead-letter → replay path; the "break it to prove recovery"
  mindset vs. "hope it works".
- **The reconciler pattern**: desired vs actual state; why controllers are
  better than cron-driven fixes (continuous, self-correcting, convergent);
  how ASG/HPA/Deployment/ArgoCD all implement it.
- **Serverless retries/DLQ**: FAILED status as an observable dead-letter; the
  correct recovery is fix-payload-then-replay-event (idempotent processing
  makes replay safe).
- **Floci honesty**: what's live (ASG replacement via launch templates, k3s
  reconcilers, DDB/S3 backup-restore, lambda invoke) vs the quirks
  (launch-configuration resources fail; ASG view shows Pending while EC2 says
  running) — and why that distinction matters when presenting local demos as
  real-AWS evidence.

## 6. Tests

`scripts/tests/test_reliability.sh` (17 checks) uses a **stateful Python fake
`aws`** (real item store, so put/scan/batch-write/delete round trips behave
like DynamoDB; `--query` extraction; Lambda lifecycle simulation) + a fake
`kubectl`. Covers: syntax, help, usage errors (exit 2), backup happy + aws-down
paths, restore with/without backups, the full drill, all three chaos targets,
scaling, reconcile report + apply + converged. Suite total is 56 script tests,
all green, shellcheck-clean.
