# Active Task State

## Current Focus
**Phase 15 — Reliability COMPLETE** (`feature/p15-reliability`, commit + PR pending). All work on disk, verified green: **17/17 reliability behavior tests** (stateful fake aws + fake kubectl, incl. a live kill-api round trip against a real uvicorn), **56 script tests total**, shellcheck clean, bash -n clean, terraform fmt + validate clean, apply idempotent. **Live-verified on Floci:** backup/restore/drill (RTO ~1s, live-count verification), chaos kill-pod (Deployment self-heal) · kill-instance (**ASG replacement ~5–9s — genuinely live with launch templates**; launch configs fail on Floci) · kill-api (kill → health fails → deploy.sh restart → recovered) · fail-image (corrupt upload → FAILED dead-letter → fix + replay S3 event → PROCESSED, **exactly 1 ProcessedCount** — double-processing fixed by resetting PENDING before the fix upload). ASG now carries explicit AZs (us-east-1a/b, real-AWS-correct). Reviewer fixes applied (circular verify, fail-image double-process, AZs, ddb_import silent-skip). Docs: docs/reliability.md + ADR-13; README/roadmap/architecture/scripts-README updated. **Next: commit + push, open PR, squash-merge; then Phase 16 — GitOps.**

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
13. [x] Phase 15 — Reliability COMPLETE (`feature/p15-reliability`): reliability.sh (backup/restore/drill RTO, chaos kill-pod/kill-instance/kill-api/fail-image, scaling, reconcile [--apply]) + 17 behavior tests + modules/autoscaling (launch template + ASG with AZs) + docs/reliability.md + ADR-13. All live-verified on Floci (ASG replacement genuinely live). Commit + PR pending.
14. [ ] Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on k3s), then troubleshooting lab & interview prep.

## Blockers / Risks
- Context loss mid-session — mitigated by continuous sync + `.ai_memory/session_log.md` (ADR-09); this session exercised recovery twice (Phase 14 on-disk-but-unrecorded; Phase 15 written as it went).
- Floci must be started before any boto3 call (run `floci start` and `eval $(floci env)`).
- `component-wise-architecture/` is a gitignored personal notes dir (ADR: excluded from audit scan).
- `feature/p15-reliability` is uncommitted — commit + push + PR + squash-merge pending (docs/source-control.md).
