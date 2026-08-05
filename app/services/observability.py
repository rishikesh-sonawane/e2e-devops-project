"""Observability service — the telemetry hub (Phase 13, ADR-11).

Three planes, all wired here so the rest of the app stays clean:

1. **Prometheus /metrics** (app/main.py exposes the registry): counters +
   histogram measuring what *this* API process does — uploads, upload
   errors, upload-processing latency.

2. **CloudWatch custom metrics** (namespace ``ImageFlow``): emitted via
   boto3 ``put_metric_data`` so the same facts the API sees are queryable
   through CloudWatch (get-metric-statistics / list-metrics) and alarmable.

3. **CloudWatch Logs** (optional): a ``logging.Handler`` that ships API log
   lines to a CloudWatch log group/stream (enabled via
   ``CLOUDWATCH_LOGS_ENABLED``). stdout stays the primary sink.

Hard rule: observability NEVER breaks the pipeline. Every CloudWatch call is
wrapped — failures are logged at debug level and swallowed. The Lambda
emits its own ProcessedCount / FailedCount metrics (see
lambda/image-processor/handler.py); the API owns Uploads / UploadErrors.
"""
from __future__ import annotations

import logging
import threading
import time
from datetime import UTC, datetime

import boto3
from prometheus_client import Counter, Histogram

from app.config.settings import get_settings

logger = logging.getLogger("imageflow.observability")

# ── Prometheus metrics (API-process scope) ───────────────────────────
UPLOADS_TOTAL = Counter(
    "imageflow_uploads_total",
    "Images uploaded through the API (accepted into S3 + DynamoDB).",
)
UPLOAD_ERRORS_TOTAL = Counter(
    "imageflow_upload_errors_total",
    "Uploads rejected with an error (cloud unavailable, etc.).",
)
UPLOAD_DURATION_SECONDS = Histogram(
    "imageflow_upload_duration_seconds",
    "Time to persist an upload (S3 put + DynamoDB record).",
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)


# ── CloudWatch custom metrics ────────────────────────────────────────
def get_cloudwatch_client():
    """CloudWatch client pointed at the local cloud (Floci) — explicit endpoint."""
    settings = get_settings()
    return boto3.client(
        "cloudwatch",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id.get_secret_value(),
        aws_secret_access_key=settings.aws_secret_access_key.get_secret_value(),
    )


def emit_metric(
    name: str,
    value: float,
    unit: str = "Count",
    *,
    dimensions: dict[str, str] | None = None,
) -> None:
    """Put one CloudWatch datapoint in the ImageFlow namespace.

    Non-fatal by design (ADR-11): if CloudWatch is down (or disabled), the
    pipeline continues — the failure is logged at debug, never raised.
    """
    settings = get_settings()
    if not settings.cloudwatch_metrics_enabled:
        return
    try:
        data = {"MetricName": name, "Value": value, "Unit": unit, "Timestamp": datetime.now(UTC)}
        if dimensions:
            data["Dimensions"] = [
                {"Name": key, "Value": value} for key, value in dimensions.items()
            ]
        get_cloudwatch_client().put_metric_data(
            Namespace=settings.cloudwatch_namespace,
            MetricData=[data],
        )
    except Exception as exc:  # noqa: BLE001 — observability must be non-fatal
        logger.debug("cloudwatch put_metric_data(%s) failed: %s", name, exc)


def emit_upload(count: int = 1) -> None:
    """Uploads accepted (S3 + DynamoDB write succeeded)."""
    emit_metric("Uploads", count)


def emit_upload_error(count: int = 1) -> None:
    """Uploads rejected with an error (503 cloud-unavailable path)."""
    emit_metric("UploadErrors", count)


# ── CloudWatch Logs (optional handler) ───────────────────────────────
def get_logs_client():
    """CloudWatch Logs client pointed at the local cloud (Floci).

    NOTE: logs is a SEPARATE boto3 service from cloudwatch (metrics/alarms)
    — the handler must use this client, not get_cloudwatch_client().
    """
    settings = get_settings()
    return boto3.client(
        "logs",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id.get_secret_value(),
        aws_secret_access_key=settings.aws_secret_access_key.get_secret_value(),
    )


class CloudWatchLogHandler(logging.Handler):
    """Ship log records to a CloudWatch log group/stream.

    Batching: records are buffered and shipped in one put_log_events call
    when the batch fills OR by a background flusher every ``flush_interval``
    seconds — a quiet API still ships its lines within one interval. Never
    raises: failures degrade to a warning log line (ADR-11).
    """

    def __init__(
        self,
        *,
        level: int = logging.INFO,
        batch_size: int = 64,
        flush_interval: float = 5.0,
    ) -> None:
        super().__init__(level=level)
        settings = get_settings()
        self._log_group = settings.cloudwatch_log_group
        self._stream = f"api-{time.strftime('%Y-%m-%dT%H-%M-%S')}"
        self._client = None
        self._sequence_token: str | None = None
        self._batch: list[dict] = []
        self._batch_size = batch_size
        self._flush_interval = flush_interval
        self._lock = threading.Lock()
        self._stop = threading.Event()
        # Background flusher: a quiet API must still ship its buffered lines
        # every flush_interval — emit-only flushing starves idle processes.
        self._thread = threading.Thread(
            target=self._flush_loop,
            name="cloudwatch-logs-flusher",
            daemon=True,
        )
        self._thread.start()

    def _flush_loop(self) -> None:
        while not self._stop.wait(self._flush_interval):
            try:
                self.flush()
            except Exception:  # noqa: BLE001 — never let the thread die loudly
                pass

    def _ensure_stream(self) -> None:
        """Create the log group/stream. Caller must hold the lock."""
        # Logs live under the separate `logs` boto3 service (not cloudwatch).
        self._client = get_logs_client()
        try:
            self._client.create_log_group(logGroupName=self._log_group)
        except Exception:  # noqa: BLE001 — group may already exist
            pass
        try:
            self._client.create_log_stream(
                logGroupName=self._log_group, logStreamName=self._stream
            )
        except Exception:  # noqa: BLE001 — stream may already exist
            pass

    def emit(self, record: logging.LogRecord) -> None:
        with self._lock:
            if self._client is None:
                try:
                    self._ensure_stream()
                except Exception:  # noqa: BLE001
                    return
            self._batch.append(
                {
                    "timestamp": int(record.created * 1000),
                    "message": self.format(record),
                }
            )
            if len(self._batch) >= self._batch_size:
                self._flush_locked()

    def flush(self) -> None:
        with self._lock:
            self._flush_locked()

    def _flush_locked(self) -> None:
        if not self._batch or self._client is None:
            return
        events, self._batch = self._batch, []
        try:
            kwargs = {
                "logGroupName": self._log_group,
                "logStreamName": self._stream,
                "logEvents": events,
            }
            if self._sequence_token:
                kwargs["sequenceToken"] = self._sequence_token
            resp = self._client.put_log_events(**kwargs)
            self._sequence_token = resp.get("nextSequenceToken")
        except Exception as exc:  # noqa: BLE001 — non-fatal by design
            # Drop the token on failure so the next flush can resync (a stale
            # token would otherwise poison every subsequent put). Events in the
            # failed batch are lost by design — telemetry never blocks the app.
            self._sequence_token = None
            logger.warning("cloudwatch logs flush failed (events lost): %s", exc)

    def close(self) -> None:
        """Stop the flusher and ship whatever is buffered (logging shutdown)."""
        self._stop.set()
        self.flush()
        super().close()
