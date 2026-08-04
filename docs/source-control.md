# ImageFlow — Source Control Strategy (Phase 2)

> The definitive rules for how this repository is branched, committed, reviewed, and released. Every assistant (Freebuff / OpenCode) and every future contribution follows this document. It is the operational companion to `AGENTS.md` §3.6–3.7.

---

## 1. The Model: GitHub Flow (deliberately simple)

This project uses **GitHub Flow** — the same model GitHub itself recommends for continuous delivery:

1. **`main` is sacred.** It is the single source of truth. It must *always* be green (all checks passing) and *always* deployable.
2. **All work happens on short-lived branches** named `feature/*`.
3. **Nothing touches `main` directly.** Every change lands via a **Pull Request (PR)** that has passing checks and a review.
4. **Branches are short-lived** — a feature branch lives a few hours to a few days, then dies after merge.

**Why not GitFlow?** GitFlow adds `develop`, `release/*`, and `hotfix/*` ceremony — designed for teams shipping scheduled releases with lots of parallel work. This project ships continuously (CI/CD in Phase 8, GitOps in Phase 16), so GitHub Flow is the right size. We keep two extra branch types *only* where they earn their keep: `hotfix/*` for urgent main fixes, and `release/*` + tags when we cut versions.

**Why this matters for interviews:** "Explain your branching strategy and why" is a classic question. The answer is: *GitHub Flow because our deployment model is continuous; GitFlow would be ceremony without benefit.*

---

## 2. Branching Strategy

| Branch | Purpose | Created from | Merged into | Lifetime |
|---|---|---|---|---|
| `main` | Source of truth; always deployable | — | — | Forever |
| `feature/<phase>-<slug>` | One unit of new work | `main` | `main` (via PR) | Short (hours–days) |
| `hotfix/<slug>` | Urgent fix on `main` (security, broken build) | `main` | `main` (via PR) | Short |
| `release/vX.Y.Z` | Version cut (used from Phase 2 tagging onward, expanded in Phase 8) | `main` | `main` + tag | Short |

### Naming rules

- All lowercase, words separated by hyphens: `feature/p10-image-pipeline`
- Prefix with the roadmap phase when the work maps to one: `feature/p2-source-control`, `feature/p9-iac-terraform`
- No issue tracker is used yet, so the slug describes the work — not an issue number.
- Good: `feature/p7-dockerfile-api`, `hotfix/config-secret-leak`
- Bad: `feature/my-branch`, `feature/fixes`, `new-stuff`

### The golden rules

1. **Never commit directly to `main`.** (Solo exception allowed only for genuine emergencies — and even then, prefer a branch + PR.)
2. **Never force-push or rewrite pushed history** on any branch that others (or CI) have seen. Rebase *local* work freely; never rebase what you already pushed.
3. **Keep branches small.** If a branch grows beyond a day of work or one logical unit, split it.

---

## 3. Commit Conventions (Conventional Commits)

Every commit message follows the **Conventional Commits** format:

```
type(scope): short imperative summary

<body: the WHY — what problem, what decision, what trade-off>
```

### Types

| Type | Use for | Example |
|---|---|---|
| `feat` | A new capability | `feat(api): add POST /api/v1/images upload endpoint` |
| `fix` | A bug fix | `fix(config): mask credentials in /config response` |
| `docs` | Documentation only | `docs(source-control): add Phase 2 git workflow` |
| `chore` | Housekeeping, tooling | `chore: pin ruff to 0.16.1` |
| `refactor` | Restructure without behavior change | `refactor(settings): extract secret masking helper` |
| `test` | Adding/fixing tests | `test(api): cover /metrics prometheus format` |
| `ci` | CI/CD config changes | `ci: add ruff + pytest jobs` |
| `build` | Build system / dependencies | `build: bump fastapi to 0.141.1` |
| `style` | Formatting, no logic change | `style: sort imports` |
| `perf` | Performance | `perf(api): cache settings lookup` |

### Message rules

- **Imperative mood** — "add", "fix", "document" — as if commanding the code. ❌ "added", "fixed stuff".
- **Summary ≤ 72 characters** (50 ideal). Long explanation goes in the body.
- **Body explains WHY, not WHAT** — the code already shows what. Reference ADRs where relevant: `Body: selects trigger via IMAGE_PROCESSING_TRIGGER (ADR-07).`
- **One logical change per commit.** Commit granularity = reviewable unit.
- **Author identity:** every commit is authored by the repository owner — **Rishikesh** — per `AGENTS.md` §3.6. Never pass `--author`, `-c user.name=`, or `GIT_AUTHOR_*`/`GIT_COMMITTER_*`.

### Good vs bad

| ❌ Bad | ✅ Good |
|---|---|
| `fixed stuff` | `fix(config): mask credentials in /config response (ADR-06)` |
| `update` | `docs(roadmap): mark Phase 2 deliverable complete` |
| `added tests and also changed docker and fixed a bug` | `feat(api): add POST /api/v1/images` (then separate commits for tests, docker) |

---

## 4. Pull Request Workflow

Every merge into `main` goes through a PR. The workflow:

```
1. Sync main          git checkout main && git pull
2. Create branch      git checkout -b feature/p3-foo
3. Small commits      git add <files> && git commit -m "feat(scope): ..."
4. Rebase on main     git fetch && git rebase origin/main   (before pushing)
5. Push               git push -u origin feature/p3-foo
6. Open PR            (title = first commit summary; use the template below)
7. Checks pass        ruff clean · pytest all green · docs updated · memory synced
8. Review             self-review + optional second opinion (OpenCode between sessions)
9. Squash merge       merge to main with ONE clean message
10. Delete branch     feature branch removed after merge
11. Sync memory       end-of-session ritual: system_state / active_task / session_log → commit
```

### PR description template

```markdown
## Summary
<!-- One sentence: what and why. -->

## Changes
- <!-- list the concrete changes -->

## Verification
- [ ] ruff check passes
- [ ] pytest passes (X/X)
- [ ] smoke test / manual verification notes

## Related
- Roadmap phase: <!-- e.g. Phase 2 -->
- ADRs: <!-- e.g. ADR-06 -->
- Memory: <!-- active_task/system_state updated? -->
```

### Definition of Done for a PR (mirrors the roadmap completion criteria)

- [ ] Implements one logical unit of work
- [ ] All checks green (ruff, pytest, and later CI from Phase 8)
- [ ] Secrets never appear in code or commits
- [ ] Docs updated where behavior/process changed
- [ ] `.ai_memory/` synced (system_state, active_task, session_log)
- [ ] Commit message follows Conventional Commits; author is Rishikesh

### Merge strategy: **squash**

- Every PR is merged with **squash merge** → `main` gets one clean, linear commit per feature.
- Why: history stays readable (`git log --oneline` = a story of features), the crash-recovery protocol (AGENTS.md §3.3) gets a clean `git log`/`git diff` to reason about, and bisecting bugs stays trivial.
- The squash commit message = the PR title (which equals the branch's first commit summary, which follows Conventional Commits). This is why the PR title format matters.

---

## 5. Release Tagging (semver)

When we cut a version (first real release in Phase 8; tags can start now):

- **Semantic Versioning:** `vMAJOR.MINOR.PATCH`
  - `MAJOR` — breaking changes
  - `MINOR` — new features, backward compatible
  - `PATCH` — bug fixes, backward compatible
- **Annotated tags** (carry a message + author):
  ```bash
  git tag -a v0.1.0 -m "release: ImageFlow v0.1.0"
  git push origin v0.1.0
  ```
- `git describe --tags` gives the nearest tag + commit count — used later for the `/version` endpoint and build metadata (`GIT_SHA` env).
- **Releases are immutable.** Never move or delete a published tag; if a release is broken, ship a `v0.1.1`.

---

## 6. Everyday Command Cheat Sheet

```bash
# Start a feature branch (from up-to-date main)
git checkout main && git pull
git checkout -b feature/p2-source-control

# Small commits
git add app/main.py
git commit -m "feat(api): add POST /api/v1/images upload endpoint"

# Rebase local work onto latest main before pushing
git fetch origin && git rebase origin/main

# Push and open a PR
git push -u origin feature/p2-source-control

# Fix the last commit (LOCAL only — never after pushing)
git commit --amend -m "feat(api): ..."

# Undo an unpushed commit but keep the changes (stage/working tree)
git reset --soft HEAD~1

# Revert a PUSHED commit (creates an inverse commit — safe on shared history)
git revert <sha>

# Grab one commit from another branch
git cherry-pick <sha>

# Stash work in progress
git stash && git stash pop

# See history as a story
git log --oneline --graph --all

# Rescue lost work (e.g. after a bad reset)
git reflog
```

### Conflict resolution (the 4 steps)

1. `git status` — see which files are in conflict.
2. Open them, keep the right lines, remove the `<<<<<<<` / `=======` / `>>>>>>>` markers.
3. `git add <resolved files>`.
4. Finish the operation: `git rebase --continue` (or `git commit` after a plain merge). **Never `--continue` before resolving all conflicts.**

---

## 7. Common Scenarios (what to do when things go sideways)

| Situation | Action |
|---|---|
| Committed to the wrong branch | `git log` the commit sha → `git checkout <right-branch>` → `git cherry-pick <sha>` → reset the wrong branch (`git reset --soft HEAD~1` if unpushed). |
| Lost work after a bad `reset` | `git reflog` → find the sha → `git reset --hard <sha>` (or `git checkout <sha> -- <file>` for one file). |
| Pushed a secret | **Never rewrite pushed history to hide it** — treat it as compromised: rotate the credential, remove it, fix hygiene (docs/setup.md §4), commit the fix. |
| `main` is behind after a review fix | Rebase your feature branch on the new `main`, re-run checks, force-push **only your own feature branch** (`git push --force-with-lease`). |
| Merge conflicts in a rebase | Section 6's 4 steps, then `git rebase --continue`. |

---

## 8. How This Ties Into the Rest of the Project

- **AGENTS.md §3.6** — commits are always authored by the repository owner (Rishikesh); no overrides ever.
- **AGENTS.md §3.3 (Crash-Safe Recovery)** — relies on a clean, linear `git log` + `git diff`; squash merges keep that story readable.
- **Phase 8 (CI/CD)** — GitHub Actions will enforce these rules automatically (conventional-commit lint, branch protection on `main`, required checks). Until then, the rules are enforced by discipline + this document.
- **Phase 16 (GitOps)** — `main` becomes the declarative source of truth for deployments; this strategy is the foundation.
- **docs/setup.md §4** — secret hygiene pairs with "never commit secrets" above.

---

*This document is the Phase 2 deliverable. The interview story: "We use GitHub Flow because we ship continuously; every change lands via a squash-merged PR with passing checks; releases are immutable semver tags."*
