# AI-Assisted Development: A Candid Retrospective

> **What it was actually like to build a 15-phase DevOps platform with an AI pair-programmer — what went wrong, where the human was irreplaceable, and the playbook for doing it better next time.**
>
> *This is the honest log of building ImageFlow with Freebuff (primary assistant) + occasional OpenCode second opinions — every incident below really happened, every fix is in git history. Written because the mistakes are worth more than the successes, and because anyone starting an AI-assisted engineering project deserves the map we had to draw ourselves.*

---

## 0. The TL;DR — ten lessons, earned the hard way

| # | Lesson | Where it bit us |
|---|--------|-----------------|
| 1 | **The AI will write confident documentation about things it never verified.** Every count drift (tests 42→53→54, modules 6→7, phases 16→19, scripts →18) came from an AI writing from memory instead of checking. **Verify before you document.** | Phase 14–15 docs, portfolio polish |
| 2 | **An emulator is a different universe.** It runs your SDK calls, but its enforcement, pagination, and persistence differ from real AWS. **Probe first, design second** — every phase here started with probes precisely because assumptions failed. | Floci quirks (ADR-07, 10, 11, 12, 13) |
| 3 | **CI is a second pair of eyes that never gets tired.** Local-vs-CI drift (shellcheck versions, shallow checkouts, image loading) caught things no human review would have. **Run the real pipeline early, not at the end.** | First CI runs, Phase 14 gates |
| 4 | **The AI's own tooling fails in boring ways.** Malformed tool calls, swallowed exceptions, background processes reaped between shells. **Treat harness artifacts as suspects, not as evidence.** | kill-api "failure", tool-call errors |
| 5 | **A full-system integration run is worth more than a thousand unit tests.** One drill caught four real bugs in a single pass — a pid off-by-one, a race, an idempotency lie, and perpetual Terraform diffs. **Run everything together, on purpose, regularly.** | The full-system drills |
| 6 | **"Idempotent" is a claim until proven.** The setup script's docs said idempotent; a re-run exited 1. **Test re-runs as first-class cases.** | `setup-inner-loop.sh` |
| 7 | **The human is the quality gate for judgment, not for typing.** Scope, cost, identity, honesty-about-limits, and "what does done mean" were always human calls. **Never delegate values to a model.** | Every phase boundary |
| 8 | **Memory must be a system, not a hope.** Sessions die; chat history is disposable. A crash-safe memory bank (append-only journal + git) made 15 phases of work recoverable. **Build continuity infrastructure before you need it.** | ADR-09, crash recovery |
| 9 | **Honesty about limits is a feature, not a weakness.** Documenting "Floci validates SigV4 but doesn't enforce IAM" is what makes the project credible. **An emulator project that pretends it's a production cloud is a liability; one that says exactly what's real is a portfolio.** | ADR-10/11/12/13 |
| 10 | **The AI accelerates, the human owns.** Every line had to be understood by the owner (that's how bugs got found — someone was actually reading). **AI is a force multiplier for a human who verifies.** | The interview-readiness requirement |

---

## 1. The collaboration model (what we set up)

Before a single phase, the project defined **how AI would work here** — this was itself a design decision and it paid off:

| Mechanism | Purpose | Where it lives |
|-----------|---------|----------------|
| **AGENTS.md** | Operating rules every AI agent must follow: memory loading, memory sync, root-cause triage, security posture, git identity | repo root |
| **`.ai_memory/` memory bank** | Stateless-defiance: `system_state.md` (what's built), `active_task.md` (what's next), `session_log.md` (append-only journal), `architectural_decisions.md` (ADRs) | `.ai_memory/` |
| **ADR-08: one primary assistant** | Freebuff continuous; OpenCode occasional second opinion only — never two assistants editing state concurrently | ADR-08 |
| **ADR-09: continuous sync** | Write to disk *as you work*, not at session end — bounded crash loss, deterministic recovery via git + journal | ADR-09 |
| **Probe-first discipline** | Every phase began by probing what the emulator *actually* does before committing to a design | all ADRs |
| **Code-review agent before merge** | Every significant change got a second-pass review; it caught real bugs in nearly every phase | PR flow |
| **Git identity rule** | Every commit authored by the repo owner — AI never impersonates | AGENTS.md §3.6 |
| **Deviation log directive** | User rule (2026-08-04): *any deviation from a written plan must be logged with cause + evidence* | ADR-10 |

**The one-line summary:** we treated the AI as a *stateless, high-throughput engineer with no memory and no judgment* — so we gave it memory (the bank), guardrails (AGENTS.md), a review layer (the reviewer agent), and kept judgment with the human.

---

## 2. What the AI was genuinely good at

Being fair matters — most of this project is working because the AI did these well:

1. **Systematic triage.** The root-cause protocol (Symptom → Root Cause → Investigation → Mitigation → Prevention) turned every failure into a documented fix, not a scramble. The CloudWatch Logs bug (`AttributeError` swallowed because `logs` is a *separate* boto3 service, not a method on `cloudwatch`) was root-caused by direct probe, fixed, and re-verified — a textbook case.
2. **Mechanical rigor at scale.** Writing 59 shell-script behavior tests with a fake `aws` CLI, faking every boto3 client for hermetic unit tests, building a stateful fake AWS for the reliability suite — this is where AI is unstoppable.
3. **Exploration without fear.** Probing Floci's CodeBuild to discover "there is no Docker daemon" and pivoting to Kaniko (ADR-10) took hours of grinding that an AI does patiently.
4. **The reviewer layer.** The code-review agent caught, in phase after phase: schema drift (DDB `N`→`S`), a pipeline aborting on one bad record, a security-scanning false positive (fake key in a test fixture), GHA permission bugs, imagePullPolicy traps. **Review-before-merge was the highest-ROI mechanism in the project.**
5. **Documentation stamina.** Rewriting README, architecture, runbooks, and this very document — the AI never gets tired of writing.
6. **Consistent process.** Every phase followed the same loop (below), which made the project feel engineered rather than improvised.

---

## 3. What went wrong — the incident log

This is the section that matters. Every incident below is real; the fixes are in git history (`git log --oneline`).

### 3.1 Cross-environment drift (the AI's home turf, and still it bit)

| Incident | Root cause | Fix | Lesson |
|----------|-----------|-----|--------|
| **First CI run failed** (`a8e9603`) | shellcheck 0.9.0 (apt, GitHub) vs 0.11.0 (brew, local) flag different warnings: `SC2317` vs `SC2329` on trap cleanup | Cross-version disables + pin CI to the same v0.11.0 binary (`f7bd092`) | **CI must match local exactly — pin toolchains, don't assume.**
| **CI shows 53 tests, local shows 54** | A live integration test runs locally (Floci up) but skips in CI (no Floci) | Documented both counts in the runbook | **Environment-dependent tests need explicit documentation.**
| **gitleaks failed on security job** | Default shallow checkout broke `base^..head` range | `fetch-depth: 0` | **Workflows need their own depth; don't inherit defaults.**
| **trivy image gate: "No such image"** | buildx `docker-container` driver with `load: false` doesn't export to the local daemon | `load: true` | **Understand your build driver's side effects.**
| **trivy HIGH CVEs** | Not app deps — **pip's vendored libraries** (msgpack, pkg_resources/setuptools) in the runtime image | Stripped pip/ensurepip from the runtime stage (smaller image + less attack surface — a win) | **Scan the artifact, not the code. And let the gate improve the artifact.**

### 3.2 Emulator-vs-real-AWS surprises (Floci quirks, all ADR-logged)

| Quirk | What actually happened | How we handled it |
|-------|----------------------|-------------------|
| `AWS_ENDPOINT_URL` inside Lambda | `localhost` in a container is the container, not the host — overriding Floci's injected endpoint breaks connectivity | Omitted the env var, documented (ADR-07) |
| k3s node can't resolve `floci-ecr-registry` | Default docker bridge has no embedded DNS → `ImagePullBackOff` | `/etc/hosts` entry on the node (documented, ephemeral) |
| CloudWatch Logs is a separate service | `AttributeError` swallowed → log group silently never created | Root-caused by probe; `boto3.client("logs")` (ADR-11) |
| Alarm actions not persisted | Alarms store state but not actions on Floci | EventBridge rule → SNS is the demonstrable alert path (ADR-11) |
| **IAM authz NOT enforced** | A one-bucket read-only user can `ListBuckets` — SigV4 validated, policy ignored | Designed real-AWS-correct; documented honestly (ADR-12) |
| WAF `probe-acl` undeletable | Floci's `get-web-acl` never returns a `LockToken` → optimistic-lock mismatch forever | Left as a harmless leftover, documented |
| No Docker in CodeBuild | Probe proved no socket/CLI/daemon → `docker build` impossible | **Kaniko daemonless builds** + `tar://` context (ADR-10, deviation logged per user directive) |
| CodeDeploy lifecycle simulated | Deployment shows `Succeeded` but appspec hooks don't execute | Status-simulation documented; configs kept real-AWS-correct |
| `launch_configuration` fails on Floci | Create returns success, describe returns empty → Terraform "empty result" | Launch templates instead — and ASG replacement is genuinely live (ADR-13) |
| `port-forward` to a Service pins one endpoint | Measured a false 100/0 canary split | Measure from *inside* the cluster (ClusterIP), not via port-forward |
| Terraform perpetual in-place diffs | Floci normalizes/normalization-drops attributes (alarm datapoints, Cognito attrs, IAM tags) | Documented `ignore_changes` → plan idempotent (PR #4) |
| AWS CLI prints literal `None` | `--query ... --output text` on a missing item → the string "None", not empty | The drill's "gone" check greps for the probe id, not any output |

**The meta-lesson:** the emulator never broke *our* code — it broke our *assumptions*. Every quirk was survivable because the process was probe-first and honesty-first. An engineer who treats the emulator as "just AWS" would have shipped a project full of silently wrong beliefs.

### 3.3 AI-introduced bugs (the uncomfortable ones — mine)

| Bug | How it happened | How it was caught | Fix |
|-----|----------------|-------------------|-----|
| **`NameError`/`F841` in observability fakes** | A global find-replace overreach renamed a variable inconsistently across tests | The test suite itself failed | Corrected the overreach; fixed `cw`/`_cw` per test |
| **`provider.tf` collapsed lines** | An edit joined two lines, silently breaking Terraform syntax | `terraform validate` / live apply | Restored formatting |
| **Docs drift (counts)** | Documentation written from memory: modules 6 vs 7, phases 16 vs 19, tests 42 vs 53 vs 54 | The code-review agent compared claims to the repo | Verified every number against the actual tree (`find`/`pytest`/`grep`) |
| **Malformed tool calls** | Repeated JSON-escaping failures in agent-spawn calls (a recurring pattern in this very session) | The tool layer rejected them | Retried with correct encoding — a reminder that AI tooling itself is a failure surface |
| **`scan_pending` pagination bug** | Carried over from Phase 14: a single non-paginated scan misses PENDING records past the first page because DynamoDB applies `Limit` *before* filtering | A dedicated pagination test simulating real paging | `ExclusiveStartKey` loop until `limit` matches or table exhausted |

**The pattern:** every AI-introduced bug came from *overreach* — a too-broad edit, an unverified claim, an assumption about behavior. None survived the review/test gauntlet. That's the design working.

### 3.4 Real bugs found by *running the whole system* (the drill's greatest hits)

These are the bugs a human+AI sitting separately would have missed. They were found by one deliberate act: **run every layer together and watch.**

1. **kill-api off-by-one pid (macOS)** — `deploy.sh` backgrounded a compound command, so `$!` captured the *wrapper subshell's* pid while uvicorn listened on pid+1. `chaos kill-api` killed the wrong process ("not running", exit 1). Fixed: resolve the real port listener (`lsof -ti tcp:$PORT -sTCP:LISTEN`) once `/health` answers; regression test asserts pidfile == real listener. *(PR #4, `eb20ed1`)*
2. **The upload-race → stuck-PENDING-forever** — the demo uploaded corrupt bytes *before* the DynamoDB record existed, so the S3 event fired while the record was absent → Lambda skipped it → never FAILED → timeout. Fixed: record-first ordering, deterministically. *(PR #4)*
3. **The same latent race in the API route** — worked only by luck of event timing. Fixed by a shared deterministic object key + **rollback** (if the upload fails, delete the record so no zombie PENDING items survive; new unit test `test_upload_failure_rolls_back_record`). *(PR #4)*
4. **`setup-inner-loop.sh` lied about idempotency** — `codedeploy create_application` lacked try/except; every sibling call handled "may exist" but this one exited 1 with `ApplicationAlreadyExistsException`. Docs claimed idempotent; a re-run proved otherwise. *(PR #6, `abb9308`)*
5. **fail-image double-processing** — the fix upload's own S3 re-trigger plus a manual invoke → `ProcessedCount` ×2. Fixed: reset to PENDING *before* the fix upload so the replay is the single deterministic retry; CloudWatch verified exactly **1** datapoint. *(ADR-13)*
6. **Restore verification was circular** — compared the manifest to the same local JSONL it was written from. Fixed: re-export the *live* table and compare counts. *(ADR-13)*
7. **Helm state stuck on the rollback-demo image** — `image.tag=broken` persisted in release values after the Phase 12 demo; every later k8s demo looked broken. Fixed live: `helm upgrade --set image.tag=latest`. **This one was pure environment state, not code — but it cost a debugging session to discover.** *(session log)*

### 3.5 False alarms and harness artifacts (what we almost "fixed" wrongly)

- **kill-api "failure"** — the API process was reaped when its spawning shell exited between test invocations; the script correctly reported "not running." It looked like a bug; a same-shell round trip proved exit 0. **Lesson: reproduce in a realistic environment before "fixing".**
- **The docs-site workflow "missing"** — I tried to trigger `docs-site.yml` (the workflow's display name) while the file is `pages.yml`; the API 404'd. Not a bug, a naming misunderstanding.
- **Browser agent couldn't reach localhost** from its sandbox — verification tooling limits, not a site problem.

**The sharp lesson:** when a test says "fails", the first question is *"is the test telling the truth about the system, or about the harness?"*

---

## 4. Where AI needed a human in the loop

This is the list of decisions the model **never** made alone — and shouldn't have:

| Decision class | Concrete examples | Why only a human could own it |
|----------------|-------------------|-------------------------------|
| **Scope & direction** | Deferring Phase 3 (Linux) and Phase 5 (Python); choosing Phase 16 (GitOps) next; ordering phases | These encode the owner's goals and constraints — the model has no agenda, so it can't pick a path |
| **Cost & risk boundaries** | Zero-cost principle (never provision real AWS); never request real credentials | A model will happily suggest services that cost money; only the human can set the "no billing meter" line |
| **Identity & ownership** | Commits authored by the owner, never the AI; AI never invents a git identity | The artifact must legally and ethically belong to the human |
| **What "done" means** | "Have you tested everything together?" — the user demanded a full-system drill the AI hadn't thought to run | The AI defined done as "phases complete"; the human defined it as "everything works together" — a deeper bar |
| **Honesty posture** | "Floci doesn't enforce IAM — document it" vs. silently designing around it | Credibility and ethics: the human decides what to *claim* publicly |
| **The understanding gate** | "I need to understand every line" — the user's interview-readiness requirement | AI can produce code it doesn't fully validate; only the human can *own* the knowledge |
| **Deviations from plan** | User directive: log every deviation with cause + evidence (ADR-10) | The human created the accountability mechanism that kept the AI honest |
| **Public exposure** | Making the repo public, choosing MIT, adding 16 topics, going for "famous on GitHub" | Personal/professional risk decisions are the owner's alone |
| **Judgment on emulator limits** | Accept "simulated" outcomes (CodeDeploy hooks) vs fighting them | Trade-offs between fidelity and time are value judgments |

**The pattern:** the human set the **constraints, the definition of done, and the truth standard**. The AI operated within those. When the AI was left unconstrained (write docs from memory), it drifted; when the human's standards were applied (verify, run it all, be honest), the result was exceptional.

---

## 5. The working loop that emerged

Every successful phase followed the same shape — this is the reusable engine:

```text
1. PROBE      → verify what the environment actually does before designing (never assume)
2. DESIGN     → write the ADR: decision + context + probe findings + honest limits
3. BUILD      → AI implements against the plan (not from imagination)
4. TEST       → hermetic unit tests + behavior tests (fake everything external)
5. VERIFY     → run it LIVE against the emulator; prove it with real outputs
6. REVIEW     → code-review agent pass; fix what it catches
7. DOCUMENT   → write the docs *after* verifying, with real numbers
8. SYNC       → append journal line, update state, commit (memory is crash-safe)
```

Phases that skipped a step paid for it:
- Skipped **VERIFY** (Phase 14 first CI push) → 3 real CI failures.
- Skipped **PROBE** (CodeBuild Docker assumption) → the whole Kaniko saga.
- Skipped **DOCUMENT-after-verify** → count drift everywhere.

---

## 6. What to avoid next time (anti-patterns)

1. **Letting the AI document from memory.** All count drift traces to this. Rule: *no number in a doc without a command that produced it.*
2. **Assuming the emulator == AWS.** Every ADR exists because an assumption was wrong. Rule: *probe anything you're about to rely on.*
3. **Treating "works locally" as "works on CI".** Shellcheck, gitleaks depth, trivy image loading — three separate traps. Rule: *run the real pipeline from day one, on the first commit of a phase.*
4. **Skipping the review agent for "small" changes.** Nearly every phase's reviewer caught something. Rule: *nothing significant merges without a second pair of eyes.*
5. **Trusting idempotency claims.** Rule: *every script that says "idempotent" must have a re-run test.*
6. **Fixing harness artifacts as code bugs.** Rule: *reproduce in a realistic environment before changing code.*
7. **Two assistants editing state.** ADR-08 exists because it's tempting. Rule: *one primary assistant; others review only.*
8. **Holding decisions in chat only.** Rule: *if it matters, it's in a file — ADR, journal, or state.*
9. **Overreach edits (global find-replace, big rewrites without diff review).** The `NameError` and collapsed-`provider.tf` both came from this. Rule: *after any bulk edit, run the full relevant test + lint before moving on.*
10. **Documenting ambitions instead of reality.** "This runs on real AWS" is the fast way to fail an interview. Rule: *the doc must say exactly what was verified and what was simulated.*

---

## 7. The playbook for your next AI-assisted project

A concrete checklist, distilled from 15 phases and 52 commits:

**Before you start (day 0)**
- [ ] Write the operating rules (AGENTS.md-style): memory, review, git identity, honesty.
- [ ] Stand up the memory bank (state + active task + append-only journal + ADR file).
- [ ] Decide the constraint lines with the human: cost, scope, public/private, definition of done.
- [ ] Build the review loop (review agent before merge) — the single highest-ROI mechanism.
- [ ] Get CI running on the *first* commit, not the last.

**While you work (every phase)**
- [ ] Probe first: prove the environment does what you assume (save the evidence).
- [ ] Write the ADR before the code (decision, context, probe findings, honest limits).
- [ ] Build + hermetic tests + **live verification** — never stop at "tests pass".
- [ ] After any bulk edit: full test + lint immediately.
- [ ] Run the **whole system together** at least once per phase — integration surfaces what units hide.
- [ ] Document only after verifying, with real numbers from real commands.
- [ ] Sync memory continuously (append journal per step), commit state at milestones.

**At the end of a session**
- [ ] Commit (deterministic recovery point) and leave the next-step in `active_task.md`.
- [ ] If the session died mid-sync: recover from git + journal tail, never from chat history.

**The human's standing jobs (non-delegable)**
- [ ] Own scope, cost, and risk decisions.
- [ ] Read the code (or at least the diffs) — understanding is the point of the exercise.
- [ ] Define "done" as *works together*, not *builds*.
- [ ] Decide the truth standard for public claims (what's real vs simulated).

---

## 8. The scorecard — 15 phases later

| Dimension | Grade | Evidence |
|-----------|-------|----------|
| **What the AI was for** | ⚡ Force multiplier | Probes, tests, docs, review loops — high-throughput, no fatigue |
| **What the human was for** | 🧭 Compass + quality gate | Scope, cost, identity, honesty, "done" definition, understanding |
| **The process that mattered most** | Review-before-merge | Caught real bugs in nearly every phase |
| **The process that caught the most bugs** | Full-system live drills | 4 real bugs in one pass (PR #4) + 2 more (PR #6) |
| **The biggest AI failure mode** | Documenting from memory | All count drift; fixed by verify-before-write |
| **The biggest human failure mode** | Trusting AI-written facts until the drill exposed them (count drift, idempotency claims); deferring Phases 3/5 left a curriculum gap | The runbook walk-throughs caught it — and the user's own standards turned every miss into a fix |
| **What survived** | 15 phases, 54 unit tests, 59 script tests, 8 PRs, CI green, live drills passing, honest docs | `git log` |

**The honest bottom line:** the AI wrote most of the code and almost all of the tests and docs — and the project works because the human never let it *decide* anything, and because we built verification (CI, review agent, live drills, memory) into the process itself. The AI was a brilliant, tireless, occasionally overconfident engineer. The human was the engineering manager who knew what "good" meant. You need both — but only one of them gets to decide what good means.

---

*See also: [AGENTS.md](https://github.com/rishikesh-sonawane/e2e-devops-project/blob/main/AGENTS.md) (the operating rules), [the memory bank](https://github.com/rishikesh-sonawane/e2e-devops-project/tree/main/.ai_memory) (the memory system), [architecture.md](architecture.md) (the system this process built), and [roadmap.md](roadmap.md) (where it's going).*
