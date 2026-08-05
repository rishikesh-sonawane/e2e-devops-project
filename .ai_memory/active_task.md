# Active Task State

## Current Focus
**Full-system live drill COMPLETE — all layers verified together on Floci, 4 loose ends fixed & shipped.** User asked "have you tested everything like together?"; ran one continuous end-to-end pass: static (53 pytest/ruff/shellcheck/58 script tests) → terraform idempotent → API upload→PROCESSED/FAILED live → observability → security → reliability (backup/drill RTO 3s/kill-instance/fail-image/scaling/reconcile) → k8s → inner-loop CodePipeline **Succeeded**. **PR #4 squash-merged as `eb20ed1`** fixing: ① kill-api macOS off-by-one pid (deploy.sh now resolves real port listener via lsof/pgrep + regression test) ② fail-image record-before-object race (stuck-PENDING bug) ③ same race in API route + rollback (delete_record on upload failure, no zombie PENDING) ④ terraform ignore_changes for Floci non-persistent attrs → plan "No changes". Also restored the k8s deployment (was stuck on Phase 12 demo `broken` image) and removed leftover probe secret. Also shipped earlier this week: manual verification runbook `docs/manual-verification.md` (PR #3, `5a88bf1`). Main clean at `eb20ed1`. **Next: Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on the k3s cluster).**

## Immediate Next Steps
1. [x] Phase 1 — FastAPI foundation: /health /version /metrics /config + config module + unit tests.
2. [x] Phase 2 — Source Control practiced end-to-end (feature branch → squash merge `1d5c3d5`).
3. [x] Phase 4 — Bash & Automation: 4 scripts + 26 tests, shellcheck clean (squash `434a333`).
4. [x] Phase 7/8 — CI-ready Dockerfile + GitHub Actions CI; **CI LIVE & GREEN** on GitHub (`f7bd092`).
5. [x] ImageFlow pipeline — upload/get/list live against Floci (`9e941dd`), 18 tests.
6. [x] Lambda image-processor — Pillow thumbnail + metadata → PROCESSED + SNS (`2065ff1`), 33/33 tests.
7. [x] Phase 9/10 — Terraform IaC live (`9b745dc`): S3/DDB/SNS/IAM/ECR/Lambda + S3→Lambda auto-delivery.
8. [x] Phase 11 — Helm chart + Floci EKS (real k3s) deployed (`51661a5`); HPA live.
9. [x] Phase 7/8 inner loop — CodePipeline → CodeBuild (Kaniko) → CodeDeploy end-to-end Succeeded (`69fe882`); ADR-10.
10. [x] Phase 12 — Deployment strategies COMPLETE (`6397127`): rolling/rollback/canary/blue-green live on k3s.
11. [x] Phase 13 — Monitoring & Observability COMPLETE (`98c51ec`): Prometheus metrics + CloudWatch metrics/logs/alarms + EventBridge→SNS; ADR-11.
12. [x] Phase 14 — Security Hardening COMPLETE **AND MERGED** (`245516e` on main, PR #1, squash): KMS, Secrets Manager (+secrets-backed creds), Cognito (real JWT flow), WAF v2, least-privilege IAM, CI gates (pip-audit/gitleaks/trivy), audit script, ADR-12, docs/security.md. CI green; the new gates caught real issues (fixed: hermetic tests, gitleaks full-history, pip-less runtime image, buildx load:true).
13. [x] Phase 15 — Reliability COMPLETE **AND MERGED** (`17a2523` on main, PR #2, squash, branch deleted): reliability.sh (backup/restore/drill RTO, chaos kill-pod/kill-instance/kill-api/fail-image, scaling, reconcile [--apply]) + 17 behavior tests + modules/autoscaling (launch template + ASG with AZs) + docs/reliability.md + ADR-13. All live-verified on Floci; CI green on PR + main.
14. [ ] Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on k3s), then troubleshooting lab & interview prep.

> **Note (deferred phases):** Phase 3 (Linux Fundamentals) and Phase 5 (Python for DevOps) are intentionally **deferred by user decision** (Aug 2026) — to be picked up later, likely folded into a fundamentals cleanup after Phase 16. Phase 5 plan (API-client CLI, backup-audit tool, YAML config-lint, docs/python-devops.md) was drafted but not started. GitOps (Phase 16) is the confirmed next phase.

## Blockers / Risks
- Context loss mid-session — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); this session exercised recovery twice (Phase 14 on-disk-but-unrecorded; Phase 15 written as it went).
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- `component-wise-architecture/` is a gitignored personal notes dir (ADR: excluded from audit scan).
- (none) — main at `17a2523`; Phase 16 — GitOps next.
