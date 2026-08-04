# ImageFlow — Free Environment Setup

Everything in this project is **100% free**. This guide installs the exact toolchain needed and wires up the AI assistant stack — **Freebuff as the primary (only continuous) assistant**, with **OpenCode + Zen "Big Pickle"** available occasionally between sessions. The goal: a complete DevOps workstation with $0 spent.

---

## 1. Core Tools (All Free)

| Tool | Why | Install |
|---|---|---|
| Git | Version control, diffs, CI triggers | https://git-scm.com |
| Python 3.12+ & pip | FastAPI app + boto3 | https://python.org |
| Docker Desktop | Containers; powers Floci's real-Docker services (Lambda, RDS, EKS, ECS…) | https://docker.com |
| AWS CLI v2 | All AWS commands against Floci | https://aws.amazon.com/cli |
| Terraform | Infrastructure as Code | https://developer.hashicorp.com/terraform/downloads (brew: `brew install hashicorp/tap/terraform`) |
| kubectl | Interact with Floci EKS (k3s) clusters | `brew install kubectl` / official docs |
| Helm | Package K8s manifests | https://helm.sh |
| Floci CLI | Start the local AWS cloud in milliseconds | `curl -fsSL https://floci.io/install.sh \| sh` |

**Deliberate omission:** Minikube / Kind are **not** needed. Floci EKS provisions a **real k3s cluster** locally, so your Kubernetes target is the same Floci toolchain as everything else (see ADR-04).

### Python Environment Hygiene

Always isolate dependencies (venv lives at the **repo root**):

```bash
# from the repository root
python -m venv .venv
source .venv/bin/activate
pip install -r app/requirements.txt
uvicorn app.main:app --reload    # run the API from the repo root
```

---

## 2. Start the Local Cloud (Floci)

**Option A — CLI (preferred):**

```bash
curl -fsSL https://floci.io/install.sh | sh
floci start
eval $(floci env)          # exports AWS_ENDPOINT_URL, dummy creds, region
```

> **No-sudo install:** the installer defaults to `/usr/local/bin` (needs sudo). To
> install without sudo: `export FLOCI_INSTALL_DIR="$HOME/.local/bin" && curl -fsSL
> https://floci.io/install.sh | sh` (note: the env var must be **exported**, not
> just prefixed to `curl`), then add `$HOME/.local/bin` to `PATH` in your shell
> profile. `floci doctor` verifies the whole setup.

**Option B — Docker Compose** (matches `floci-compose.yml` in the repo):

```bash
docker compose -f floci-compose.yml up -d
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
```

> **No real credentials ever.** `test`/`test` is all Floci requires. Freebuff (and OpenCode, when used) reads your terminal output and these exports when debugging deployment errors against the local cloud.

### Verify Everything Works

```bash
aws --version
docker --version
terraform version
kubectl version --client
helm version
floci doctor            # checks the emulator + docker socket

# Smoke test the cloud
aws s3 mb s3://imageflow-check
aws dynamodb list-tables
```

---

## 3. AI Assistant Setup — Freebuff Primary, OpenCode Zen Occasional

This project deliberately runs **one continuous assistant**: **Freebuff**. No multi-provider config files, no API-key juggling, no competing contexts. A second, optional assistant — **OpenCode** with the Zen **Big Pickle** model — is used *between* sessions for independent deep dives or second opinions, but is never required for continuous work (see ADR-08).

### 3.1 Freebuff — Primary Assistant (always on)

- **What:** A free AI coding chat (freebuff.com). Everything in this repo is designed around it.
- **Setup:** Open https://freebuff.com in your browser next to your editor. No install, no API keys.
- **Context:** At the start of every session, Freebuff reads the `.ai_memory/` files and `AGENTS.md` to resume exactly where you left off (see §5). The Memory Sync Protocol (`AGENTS.md` §3.2) keeps those files fresh at the end of every working session.

### 3.2 OpenCode + Zen "Big Pickle" — Occasional Second Opinion

- **What:** [OpenCode](https://opencode.ai) is a free, open-source terminal AI coding agent. **OpenCode Zen** is its curated model gateway; **Big Pickle** (`big-pickle`) is a stealth model currently offered **free** on Zen (trial period). Treat it as a non-production, second-opinion tool — and never paste real secrets into it (free-trial sessions may be used to improve the model).
- **Install:**
  ```bash
  curl -fsSL https://opencode.ai/install | bash
  ```
- **Connect Zen + pick the model:**
  ```bash
  cd <this repo>
  opencode
  /connect        # choose OpenCode Zen, follow the auth flow
  /models         # select big-pickle
  ```
- **Usage pattern:** OpenCode reads `AGENTS.md` automatically (run `/init` once if prompted) and must be pointed at the same `.ai_memory/` files. Use it *between* Freebuff sessions — e.g., an independent review of a tricky Terraform module or Helm chart — then bring the outcome back so Freebuff records it in `.ai_memory/`.

> **Rule of thumb:** Freebuff is the single source of truth for project state. Anything OpenCode produces must be synced back into `.ai_memory/` (or committed) before it counts as done.

### 3.3 Recommended VS Code Extensions (Free, editor-only)

Freebuff and OpenCode drive the workflow, but these extensions keep the editor honest (syntax, linting, validation):

- HashiCorp Terraform — HCL syntax
- Kubernetes by Microsoft — manifest validation
- YAML by Red Hat — Helm / GHA indentation
- Docker by Microsoft — containers in the sidebar
- Ruff — Python linting/formatting

---

## 4. Git & Secret Hygiene

1. `git init` at the project root.
2. The **production-ready `.gitignore` is committed at the repo root** — it blocks secrets, `.env`, `*.pem`, Terraform state, `.venv`, Python caches, Floci data, logs, and editor files. Review it before committing anything.

> Your real AWS keys (if any exist anywhere on this machine) must never be committed. In this project you will only ever use dummy `test`/`test` credentials for Floci.

---

## 5. AI Memory Bank

This repo includes a persistent memory system (see `AGENTS.md`). **The full how-to lives in [`.ai_memory/README.md`](../.ai_memory/README.md)** — start there:

- `.ai_memory/README.md` — how-to guide (load → sync → commit → recover)
- `.ai_memory/SYSTEM_CONTEXT.md` — structural anchor
- `.ai_memory/system_state.md` — what's built
- `.ai_memory/active_task.md` — what's next
- `.ai_memory/architectural_decisions.md` — ADRs
- `.ai_memory/session_log.md` — raw activity trail (crash-safe)

**Start each Freebuff session** (and any OpenCode session) by having the assistant load the memory:

```
Read .ai_memory/ and AGENTS.md. Check git status/diff and the session_log.md tail for anything done since the last sync. What's our status and next step?
```

**End each working session** by having the assistant output the Memory Sync snippet (`AGENTS.md` §3.2) and apply it to `.ai_memory/system_state.md` / `.ai_memory/active_task.md`. That way any future session — even with all chat history deleted — resumes exactly where you left off.
