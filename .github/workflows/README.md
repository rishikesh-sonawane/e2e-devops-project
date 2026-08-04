# .github/workflows/ — CI/CD (outer loop)

| Workflow | Purpose | Status |
|---|---|---|
| `ci.yml` | Quality gate: ruff lint → shellcheck → pytest unit tests → Docker image build | ✅ written, validated locally with `act`; goes live when the repo gains a GitHub remote |
| `deploy.yml` / `release.yml` | Planned (Phase 8) | ⬜ |
