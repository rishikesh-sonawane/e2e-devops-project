"""Unit tests for the observability service (Phase 13, ADR-11).

Covers: Prometheus counters on uploads, CloudWatch metric emission shape,
non-fatal behavior (CloudWatch down never breaks the pipeline), the
config gate, and the optional CloudWatchLogHandler.
"""
import logging
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import observability
from app.tests.fakes import FakeCloudWatch

client = TestClient(app)


@pytest.fixture(autouse=True)
def fake_cw(monkeypatch):
    fake = FakeCloudWatch()
    monkeypatch.setattr(observability, "get_cloudwatch_client", lambda: fake)
    return fake


def _upload() -> dict:
    resp = client.post(
        "/api/v1/images",
        files={"file": ("photo.png", b"not-a-real-image", "image/png")},
    )
    assert resp.status_code == 201  # bytes are stored as-is; decode happens later
    return resp.json()


# ── Prometheus side ──────────────────────────────────────────────────

def _counter_value(counter) -> float:
    """Current value of a Prometheus counter via its public collect() API."""
    return counter.collect()[0].samples[0].value


def test_metrics_expose_pipeline_counters(fake_cw) -> None:
    before = _counter_value(observability.UPLOADS_TOTAL)
    _upload()
    assert _counter_value(observability.UPLOADS_TOTAL) == before + 1

    resp = client.get("/metrics")
    assert resp.status_code == 200
    text = resp.text
    for metric in (
        "imageflow_http_requests_total",
        "imageflow_uptime_seconds",
        "imageflow_uploads_total",
        "imageflow_upload_errors_total",
        "imageflow_upload_duration_seconds",
    ):
        assert metric in text


def test_upload_error_increments_error_counter(monkeypatch, fake_cw) -> None:
    """A failing cloud write must bump upload_errors_total, not uploads — and
    emit the CloudWatch UploadErrors datapoint."""

    def _boom(*args, **kwargs):
        raise RuntimeError("s3 down")

    uploads_before = _counter_value(observability.UPLOADS_TOTAL)
    errors_before = _counter_value(observability.UPLOAD_ERRORS_TOTAL)
    with patch("app.services.storage.upload_original", side_effect=_boom):
        resp = client.post(
            "/api/v1/images", files={"file": ("x.png", b"data", "image/png")}
        )
    assert resp.status_code == 503
    assert _counter_value(observability.UPLOADS_TOTAL) == uploads_before
    assert _counter_value(observability.UPLOAD_ERRORS_TOTAL) == errors_before + 1
    assert any(
        dp["MetricData"][0]["MetricName"] == "UploadErrors" for dp in fake_cw.datapoints
    )


# ── CloudWatch emission ──────────────────────────────────────────────

def test_upload_emits_cloudwatch_metric(fake_cw) -> None:
    _upload()
    assert len(fake_cw.datapoints) == 1
    call = fake_cw.datapoints[0]
    assert call["Namespace"] == "ImageFlow"
    (point,) = call["MetricData"]
    assert point["MetricName"] == "Uploads"
    assert point["Value"] == 1
    assert point["Unit"] == "Count"


def test_emit_metric_supports_dimensions(fake_cw) -> None:
    observability.emit_metric("Uploads", 1, dimensions={"source": "test"})
    call = fake_cw.datapoints[0]
    assert call["MetricData"][0]["Dimensions"] == [{"Name": "source", "Value": "test"}]


def test_emit_metric_non_fatal_when_cloudwatch_down(monkeypatch, fake_cw) -> None:
    def _boom(*args, **kwargs):
        raise RuntimeError("cloudwatch unreachable")

    monkeypatch.setattr(observability, "get_cloudwatch_client", _boom)
    observability.emit_metric("Uploads", 1)  # must not raise
    assert fake_cw.datapoints == []  # nothing reached the fake


def test_emit_metric_disabled_via_settings(monkeypatch, fake_cw) -> None:
    monkeypatch.setattr(observability.get_settings(), "cloudwatch_metrics_enabled", False)
    observability.emit_metric("Uploads", 1)
    assert fake_cw.datapoints == []


# ── CloudWatchLogHandler ─────────────────────────────────────────────

def test_log_handler_ships_records_and_is_non_fatal(fake_cw, monkeypatch) -> None:
    monkeypatch.setattr(observability, "get_logs_client", lambda: fake_cw)
    handler = observability.CloudWatchLogHandler(level=logging.INFO)
    logger = logging.getLogger("imageflow.test-observer")
    # pytest's logging plugin raises the root level to WARNING during runs,
    # so the logger itself must be explicitly INFO for records to flow.
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    try:
        logger.info("hello observability")
        handler.flush()
        assert fake_cw.log_events  # one put_log_events call shipped
        assert fake_cw.log_events[0]["logGroupName"] == "/imageflow/api"
        assert fake_cw.log_events[0]["logEvents"][0]["message"]
    finally:
        logger.removeHandler(handler)
        handler.close()


def test_log_handler_never_raises_on_broken_client(monkeypatch) -> None:
    def _boom(*args, **kwargs):
        raise RuntimeError("logs down")

    monkeypatch.setattr(observability, "get_logs_client", _boom)
    handler = observability.CloudWatchLogHandler(level=logging.INFO)
    logger = logging.getLogger("imageflow.test-observer-broken")
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    try:
        logger.info("this must not raise")
        handler.flush()
    finally:
        logger.removeHandler(handler)
        handler.close()
