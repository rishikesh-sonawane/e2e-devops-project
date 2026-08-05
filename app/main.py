"""ImageFlow API — application foundation (Phase 1).

Run from the repository root:

    source .venv/bin/activate
    uvicorn app.main:app --reload

Ops endpoints: /health · /version · /metrics · /config
"""
from __future__ import annotations

import logging
import platform
import subprocess
import time
from datetime import UTC, datetime

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest

from app.config.settings import get_settings
from app.routes import images
from app.services.observability import CloudWatchLogHandler

settings = get_settings()

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("imageflow")

# Optional CloudWatch Logs sink (CLOUDWATCH_LOGS_ENABLED=true) — non-fatal,
# ships the same lines that go to stdout (Phase 13, ADR-11).
if settings.cloudwatch_logs_enabled:
    cw_handler = CloudWatchLogHandler()
    cw_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    logging.getLogger().addHandler(cw_handler)
    logger.info("cloudwatch logs enabled → group %s", settings.cloudwatch_log_group)

APP_STARTED_AT = time.time()


# ── Build metadata ───────────────────────────────────────────────────
def _resolve_git_sha() -> str:
    """Short git SHA — from GIT_SHA env (CI/build) or live `git rev-parse`."""
    if settings.git_sha:
        return settings.git_sha
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        logger.warning("git unavailable — reporting git_sha=unknown")
    return "unknown"


GIT_SHA = _resolve_git_sha()
BUILD_TIMESTAMP = settings.build_timestamp or datetime.now(UTC).isoformat()

# ── Prometheus metrics ───────────────────────────────────────────────
HTTP_REQUESTS = Counter(
    "imageflow_http_requests_total",
    "Total HTTP requests handled by the API",
    ["method", "path"],
)
UPTIME = Gauge("imageflow_uptime_seconds", "Seconds since the API process started")
UPTIME.set_function(lambda: time.time() - APP_STARTED_AT)

app = FastAPI(
    title="ImageFlow API",
    version=settings.app_version,
    description=(
        "Event-driven image pipeline — upload, process, index, notify. "
        "Runs locally on Floci for $0 (see docs/architecture.md)."
    ),
)

app.include_router(images.router)


@app.middleware("http")
async def count_requests(request: Request, call_next):
    response = await call_next(request)
    HTTP_REQUESTS.labels(method=request.method, path=request.url.path).inc()
    return response


@app.get("/", include_in_schema=False)
def root() -> dict:
    return {"service": settings.app_name, "docs": "/docs", "health": "/health"}


@app.get("/health", tags=["ops"], summary="Liveness probe")
def health() -> dict:
    """Liveness probe — 200 whenever the process is up."""
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.environment,
    }


@app.get("/version", tags=["ops"], summary="Build version info")
def version() -> dict:
    """Version info — git SHA + build timestamp (env-injectable at build time)."""
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "git_sha": GIT_SHA,
        "build_timestamp": BUILD_TIMESTAMP,
        "python": platform.python_version(),
    }


@app.get("/metrics", tags=["ops"], summary="Prometheus-format metrics")
def metrics() -> Response:
    """Prometheus exposition format (see docs/architecture.md §3.7)."""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/config", tags=["ops"], summary="Runtime configuration (secrets masked)")
def config() -> dict:
    """Runtime configuration dump. Secret fields are masked (AGENTS.md §3.5)."""
    return settings.safe_config()
