"""Unit tests for the ImageFlow Phase 1 foundation endpoints."""
from fastapi.testclient import TestClient

from app.config.settings import get_settings
from app.main import app

client = TestClient(app)


def test_health_ok() -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "imageflow"


def test_version_ok() -> None:
    resp = client.get("/version")
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "imageflow"
    assert body["version"]
    assert body["git_sha"]  # short sha or "unknown"


def test_metrics_prometheus_format() -> None:
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "imageflow_http_requests_total" in resp.text
    assert "imageflow_uptime_seconds" in resp.text


def test_config_masks_secrets() -> None:
    resp = client.get("/config")
    assert resp.status_code == 200
    body = resp.json()
    assert body["aws_secret_access_key"] == "***"
    assert body["aws_access_key_id"] == "***"
    # Non-secret values pass through untouched — compared against the live
    # settings (env-aware: `eval $(floci env)` changes the endpoint URL).
    assert body["aws_endpoint_url"] == get_settings().aws_endpoint_url
    assert body["image_processing_trigger"] == get_settings().image_processing_trigger


def test_root_links() -> None:
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["docs"] == "/docs"
    assert body["health"] == "/health"
