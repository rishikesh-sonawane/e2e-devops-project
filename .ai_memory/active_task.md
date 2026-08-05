# Active Task State

## Current Focus
**WIKI LIVE (PR #11 `7d83fd9`) — companion wiki with 4 pages (Home, Quick-Start, FAQ, Learning-Journey) set up; pointer design links to canonical docs site. AI-DEV RETROSPECTIVE DONE — PR #9 merged `4c97339`:** new `docs/ai-assisted-development.md` (candid retrospective of building ImageFlow with AI: incident log — cross-env drift, emulator quirks, AI-introduced bugs, drill-found bugs, harness artifacts; where the human was irreplaceable; the working loop; anti-patterns; next-project playbook; scorecard). Cross-linked mkdocs nav + index + README; strict build green; CI green (4 checks). Prior: GitHub Pages docs site (PR #8 `a9387d7`), portfolio docs (PR #7 `6c1be72`). Main clean at `4c97339`. **Next: Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on the k3s cluster).**

Prior: portfolio docs (PR #7 `6c1be72` — README/architecture rewrite, DEVELOPER.md, MIT LICENSE, repo description + 16 topics), manual runbook walk-through (PR #6 `abb9308`), docs update (PR #5 `704dc22`), live drill + 4 fixes (PR #4 `eb20ed1`), runbook (PR #3 `5a88bf1`). Main clean. **Next: Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on the k3s cluster).**

---

*Below: pre-drill state, superseded.*

**FULL MANUAL RUNBOOK WALK-THROUGH COMPLETE — user asked "have you done a manual test yet?" → ran the entire system end-to-end against `docs/manual-verification.md` (Phases 0–9), live on Floci, on current main.** All green: 54 pytest (36 app + 17 lambda + 1 live integration), ruff/shellcheck, 59 script tests, terraform "No changes" + inventory, upload→PROCESSED instant + junk→FAILED, k8s pod + HPA + port-forward health, inner-loop CodePipeline **Succeeded**, observability + security.sh all + audit, reliability (backup 81 items, drill RTO 4s, kill-instance 7s, fail-image, scaling, reconcile), kill-api round trip exit 0, GitHub CI green. **Two more loose ends fixed (PR #6, squash `abb9308`):** ① `setup-inner-loop.sh` not idempotent (create_application lacked try/except → exit 1 on re-run) — fixed, proven exit 0; ② runbook pytest count 53→54 (live integration test runs locally, skips in CI). Cleaned leftover probe resources (probe-pool, probe-user; probe-acl WAF is a harmless Floci lock-token quirk). Prior this week: live drill + 4 fixes (PR #4 `eb20ed1`), docs update (PR #5 `704dc22`), runbook (PR #3 `5a88bf1`). Main clean at `abb9308`. **Next: Phase 16 — GitOps (Flux/ArgoCD-style declarative sync on the k3s cluster).**

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
