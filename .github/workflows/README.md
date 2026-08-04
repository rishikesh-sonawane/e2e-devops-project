# .github/workflows/ — CI/CD (outer loop)

| Workflow | Purpose | Status |
|---|---|---|
| `ci.yml` | Quality gate: ruff lint → shellcheck → pytest unit tests → Docker image build | ✅ **LIVE & GREEN** on GitHub (every push; shellcheck pinned to v0.11.0) |
| `deploy.yml` / `release.yml` | Planned (Phase 8) | ⬜ |
