# syntax=docker/dockerfile:1
#
# ImageFlow API — production Dockerfile (Phase 7).
#
# Multi-stage build:
#   Stage 1 (builder): install pinned deps into a dedicated venv
#   Stage 2 (runtime): non-root python:3.12-slim with only the venv + app
#
# Build:  docker build -t imageflow-api:latest .
# Run:    docker run -p 8000:8000 imageflow-api:latest

# ── Stage 1: build ──────────────────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

COPY app/requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt

# ── Stage 2: runtime ────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# Build metadata (inject via --build-arg GIT_SHA=... BUILD_TIMESTAMP=...)
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
LABEL org.opencontainers.image.revision=$GIT_SHA \
      build.timestamp=$BUILD_TIMESTAMP

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app ./app

# Non-root runtime user (least privilege — AGENTS.md §3.5)
RUN useradd --create-home --uid 1000 imageflow \
    && chown -R imageflow:imageflow /app
USER imageflow

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
