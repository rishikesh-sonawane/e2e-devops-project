"""Unit tests for the image-processor handler — offline, deterministic.

The handler's ``_clients`` registry is injected with in-memory fakes so no
cloud (or even boto3) is required. ``lambda/`` is a Python keyword, so tests
add the handler's directory to ``sys.path`` and import the module directly.
"""
from __future__ import annotations

import hashlib
import json
import sys
from io import BytesIO
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import handler  # noqa: E402
from fakes import FakeDDB, FakeS3, FakeSNS  # noqa: E402


@pytest.fixture(autouse=True)
def isolated_clients(monkeypatch):
    """Fresh fake AWS clients + clean module state for every test."""
    monkeypatch.setattr(handler, "_clients", {})
    s3, ddb, sns = FakeS3(), FakeDDB(), FakeSNS()
    handler._clients.update({"s3": s3, "dynamodb": ddb, "sns": sns})
    return s3, ddb, sns


def _png(width: int = 300, height: int = 200) -> bytes:
    buf = BytesIO()
    Image.new("RGB", (width, height), (200, 30, 60)).save(buf, format="PNG")
    return buf.getvalue()


def _typed_record(image_id: str, status: str = "PENDING") -> dict:
    return {
        "image_id": {"S": image_id},
        "filename": {"S": "photo.png"},
        "content_type": {"S": "image/png"},
        "size": {"N": "123"},
        "status": {"S": status},
        "original_key": {"S": f"uploads/{image_id}/photo.png"},
        "uploaded_at": {"S": "2026-08-04T00:00:00+00:00"},
    }


def _seed(s3, ddb, image_id: str, data: bytes | None, status: str = "PENDING") -> None:
    """Seed a DDB record; also place the original in S3 when data is given."""
    ddb.put_item(TableName="ImageFlowMetadata", Item=_typed_record(image_id, status))
    if data is not None and s3 is not None:
        key = f"uploads/{image_id}/photo.png"
        uploads = s3.objects.setdefault("imageflow-uploads", {})
        uploads[key] = {"Body": data, "ContentType": "image/png"}


# ── S3 event parsing ──────────────────────────────────────────────────

def test_parse_s3_event_extracts_image_ids() -> None:
    event = {
        "Records": [
            {
                "s3": {
                    "object": {"key": "uploads/abc-123/photo.png"},
                }
            },
            {
                "s3": {
                    "object": {"key": "uploads/def-456/pic.jpg"},
                }
            },
        ]
    }
    assert handler.parse_s3_event(event) == ["abc-123", "def-456"]


def test_parse_s3_event_ignores_non_uploads_keys() -> None:
    event = {
        "Records": [
            {"s3": {"object": {"key": "thumbs/abc-123/photo.png"}}},
            {"s3": {"object": {"key": "uploads//empty.png"}}},
            {"s3": {"object": {"key": ""}}},
        ]
    }
    assert handler.parse_s3_event(event) == []


# ── Happy path ────────────────────────────────────────────────────────

def test_process_image_happy_path(isolated_clients) -> None:
    s3, ddb, sns = isolated_clients
    data = _png(300, 200)
    _seed(s3, ddb, "img-1", data)

    result = handler.process_image("img-1")

    assert result["status"] == "PROCESSED"
    assert result["thumbnail_key"] == "thumbs/img-1/photo.png"

    # Thumbnail physically stored in the thumbs bucket.
    assert "imageflow-thumbs" in s3.objects
    thumb = s3.objects["imageflow-thumbs"]["thumbs/img-1/photo.png"]["Body"]
    with Image.open(BytesIO(thumb)) as img:
        assert img.format == "PNG"
        assert img.width <= 256 and img.height <= 256

    # Record updated with metadata + status.
    record = ddb.items["img-1"]
    assert record["status"]["S"] == "PROCESSED"
    assert record["format"]["S"] == "PNG"
    assert record["width"]["S"] == "300"
    assert record["height"]["S"] == "200"
    assert record["sha256"]["S"] == hashlib.sha256(data).hexdigest()
    assert "thumbnail_key" in record and "processed_at" in record

    # Exactly one SNS event, correctly shaped.
    assert len(sns.published) == 1
    msg = sns.published[0]
    assert msg["Subject"] == "image.processed"
    payload = json.loads(msg["Message"])
    assert payload["image_id"] == "img-1"
    assert payload["event"] == "image.processed"
    assert payload["format"] == "PNG"


def test_thumbnail_preserves_aspect_ratio_and_caps_at_256(isolated_clients) -> None:
    s3, ddb, _ = isolated_clients
    data = _png(800, 400)  # 2:1
    _seed(s3, ddb, "img-wide", data)

    handler.process_image("img-wide")

    thumb = s3.objects["imageflow-thumbs"]["thumbs/img-wide/photo.png"]["Body"]
    with Image.open(BytesIO(thumb)) as img:
        assert img.width == 256
        assert img.height == 128  # 800x400 → 256x128 exactly


# ── Failure paths ─────────────────────────────────────────────────────

def test_process_image_fails_on_non_image(isolated_clients) -> None:
    s3, ddb, sns = isolated_clients
    _seed(s3, ddb, "img-bad", b"this is definitely not an image")

    result = handler.process_image("img-bad")

    assert result["status"] == "FAILED"
    assert ddb.items["img-bad"]["status"]["S"] == "FAILED"
    assert "error" in ddb.items["img-bad"]
    assert "imageflow-thumbs" not in s3.objects
    assert sns.published == []


def test_process_image_fails_when_s3_object_missing(isolated_clients) -> None:
    _, ddb, _ = isolated_clients
    _seed(s3=None, ddb=ddb, image_id="img-gone", data=None)

    result = handler.process_image("img-gone")

    assert result["status"] == "FAILED"
    assert ddb.items["img-gone"]["status"]["S"] == "FAILED"


def test_process_image_fails_on_missing_original_key(isolated_clients) -> None:
    s3, ddb, _ = isolated_clients
    record = _typed_record("img-nokey")
    record.pop("original_key")
    ddb.put_item(TableName="ImageFlowMetadata", Item=record)
    data = _png()
    s3.objects.setdefault("imageflow-uploads", {})["uploads/img-nokey/photo.png"] = {
        "Body": data
    }

    result = handler.process_image("img-nokey")

    assert result["status"] == "FAILED"
    assert result["reason"] == "missing original_key"


# ── Idempotency / edge cases ─────────────────────────────────────────

def test_process_image_skips_already_processed(isolated_clients) -> None:
    s3, ddb, sns = isolated_clients
    _seed(s3, ddb, "img-done", _png(), status="PROCESSED")

    result = handler.process_image("img-done")

    assert result["status"] == "SKIPPED"
    assert result["reason"] == "already processed"
    assert sns.published == []
    assert "imageflow-thumbs" not in s3.objects


def test_process_image_skips_missing_record(isolated_clients) -> None:
    result = handler.process_image("img-unknown")
    assert result["status"] == "SKIPPED"
    assert result["reason"] == "missing record"


def test_process_pending_processes_only_pending(isolated_clients) -> None:
    s3, ddb, sns = isolated_clients
    data = _png()
    _seed(s3, ddb, "img-p1", data)
    _seed(s3, ddb, "img-p2", data)
    _seed(s3, ddb, "img-done", data, status="PROCESSED")
    _seed(s3, ddb, "img-bad", b"not an image")

    count = handler.process_pending()

    assert count == 2
    assert ddb.items["img-p1"]["status"]["S"] == "PROCESSED"
    assert ddb.items["img-p2"]["status"]["S"] == "PROCESSED"
    assert ddb.items["img-bad"]["status"]["S"] == "FAILED"
    assert len(sns.published) == 2


def test_lambda_handler_processes_s3_event(isolated_clients) -> None:
    s3, ddb, _ = isolated_clients
    _seed(s3, ddb, "img-ev", _png())

    response = handler.lambda_handler(
        {"Records": [{"s3": {"object": {"key": "uploads/img-ev/photo.png"}}}]}
    )

    assert response["statusCode"] == 200
    assert response["processed"] == 1
    assert response["results"][0]["status"] == "PROCESSED"


def test_size_keeps_numeric_type_after_processing(isolated_clients) -> None:
    """The get→merge→put round trip must not flip `size` from N to S."""
    s3, ddb, _ = isolated_clients
    _seed(s3, ddb, "img-size", _png())

    handler.process_image("img-size")

    assert ddb.items["img-size"]["size"]["N"] == "123"


def test_process_pending_continues_after_failure(isolated_clients, monkeypatch) -> None:
    """One raising image must not abort the rest of the batch."""
    s3, ddb, _ = isolated_clients
    data = _png()
    _seed(s3, ddb, "img-ok1", data)
    _seed(s3, ddb, "img-ok2", data)
    ddb.put_item(TableName="ImageFlowMetadata", Item=_typed_record("img-crash"))
    original_process = handler.process_image

    def _boom(image_id):
        if image_id == "img-crash":
            raise RuntimeError("simulated crash")
        return original_process(image_id)

    monkeypatch.setattr(handler, "process_image", _boom)

    count = handler.process_pending()

    assert count == 2  # img-ok1 + img-ok2 still processed
    assert ddb.items["img-ok1"]["status"]["S"] == "PROCESSED"
    assert ddb.items["img-ok2"]["status"]["S"] == "PROCESSED"
