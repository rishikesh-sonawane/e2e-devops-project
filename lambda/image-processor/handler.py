"""image-processor Lambda — thumbnail generation + metadata extraction.

The "process" step of the ImageFlow pipeline (ADR-01, ADR-06):

    1. Reads the original from S3 (uploads bucket, ``uploads/`` prefix).
    2. Pillow: extracts metadata (format, mode, width, height, SHA-256).
    3. Generates a 256px aspect-preserving thumbnail → thumbs bucket.
    4. Updates the DynamoDB record to ``PROCESSED`` (+ metadata + thumbnail key).
    5. Publishes an ``image.processed`` event to the SNS topic.

This module is a **standalone deployable unit**: it imports nothing from
``app/``. It runs inside a custom Docker image (public Lambda Python base +
Pillow) pushed to Floci ECR, and is exercised locally through its Python
functions.

Trigger paths (ADR-07, ``IMAGE_PROCESSING_TRIGGER``):
- ``s3``       — ``lambda_handler()`` parses an ``s3:ObjectCreated:*`` event
                 (primary, classic event-driven serverless).
- ``direct``   — ``process_pending()`` scans DynamoDB for PENDING records and
                 processes each (fallback B — used by scripts/process-pending.sh
                 when Floci cannot wire S3 → Lambda).
- ``dynamodb`` — (planned) event source mapping from DynamoDB Streams.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import UTC, datetime
from io import BytesIO

import boto3
from PIL import Image, UnidentifiedImageError

logger = logging.getLogger("image-processor")

# ── Configuration (env-driven; mirrors app/config/settings.py defaults) ─
UPLOADS_BUCKET = os.environ.get("IMAGEFLOW_UPLOADS_BUCKET", "imageflow-uploads")
THUMBS_BUCKET = os.environ.get("IMAGEFLOW_THUMBS_BUCKET", "imageflow-thumbs")
METADATA_TABLE = os.environ.get("IMAGEFLOW_METADATA_TABLE", "ImageFlowMetadata")
SNS_TOPIC = os.environ.get("IMAGEFLOW_SNS_TOPIC", "imageflow-events")
AWS_ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566")
AWS_REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
THUMB_MAX = 256  # longest edge of the thumbnail, pixels

# Pillow format name → HTTP content type for the stored thumbnail.
_MIME = {
    "PNG": "image/png",
    "JPEG": "image/jpeg",
    "WEBP": "image/webp",
    "GIF": "image/gif",
    "BMP": "image/bmp",
    "TIFF": "image/tiff",
}

_clients: dict[str, object] = {}


def _client(service: str):
    """Per-service singleton boto3 client (explicit Floci endpoint, AGENTS.md §2)."""
    if service not in _clients:
        _clients[service] = boto3.client(
            service,
            endpoint_url=AWS_ENDPOINT_URL,
            region_name=AWS_REGION,
            aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
            aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
        )
    return _clients[service]


# ── Image work (pure functions, fully unit-testable) ──────────────────

def extract_metadata(data: bytes) -> dict:
    """Metadata from image bytes: format, mode, dimensions, SHA-256."""
    sha256 = hashlib.sha256(data).hexdigest()
    with Image.open(BytesIO(data)) as img:
        return {
            "format": (img.format or "UNKNOWN").upper(),
            "mode": img.mode,
            "width": img.width,
            "height": img.height,
            "sha256": sha256,
        }


def make_thumbnail(data: bytes, max_size: int = THUMB_MAX) -> bytes:
    """Aspect-ratio-preserving thumbnail in the original image format."""
    with Image.open(BytesIO(data)) as img:
        img.thumbnail((max_size, max_size))
        out = BytesIO()
        img.save(out, format=img.format or "PNG")
        return out.getvalue()


def _now() -> str:
    return datetime.now(UTC).isoformat()


# ── DynamoDB helpers ──────────────────────────────────────────────────

def _deserialize(item: dict) -> dict:
    """DynamoDB typed map → plain dict of values."""
    return {key: next(iter(values.values())) for key, values in item.items()}


def _typed(item: dict) -> dict:
    """Plain dict → DynamoDB typed item.

    Type-stable round trip: every value becomes ``{"S": str}`` except the
    schema's numeric field ``size``, which stays ``{"N": str}`` so it never
    flips N→S after processing (which would break numeric queries/reports).
    """
    out: dict = {}
    for key, value in item.items():
        if key == "size":
            out[key] = {"N": str(value)}
        else:
            out[key] = {"S": str(value)}
    return out


def _put_record(client, record: dict) -> dict:
    """Idempotent full-item write (get → merge → put). Expects a typed item."""
    client.put_item(TableName=METADATA_TABLE, Item=record)
    return _deserialize(record)


def get_record(client, image_id: str) -> dict | None:
    resp = client.get_item(TableName=METADATA_TABLE, Key={"image_id": {"S": image_id}})
    item = resp.get("Item")
    return _deserialize(item) if item else None


def scan_pending(client, limit: int = 50) -> list[dict]:
    """Scan for records still in ``PENDING`` status (direct-mode trigger)."""
    resp = client.scan(
        TableName=METADATA_TABLE,
        FilterExpression="#s = :pending",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":pending": {"S": "PENDING"}},
        Limit=limit,
    )
    return [_deserialize(item) for item in resp.get("Items", [])]


# ── SNS helpers ───────────────────────────────────────────────────────

def ensure_topic(client) -> str:
    """Return the topic ARN, creating it if needed (create_topic is idempotent)."""
    return client.create_topic(Name=SNS_TOPIC)["TopicArn"]


def publish_event(client, image_id: str, payload: dict) -> str:
    """Publish an event to the SNS topic; returns the MessageId."""
    topic_arn = ensure_topic(client)
    resp = client.publish(
        TopicArn=topic_arn,
        Subject=payload.get("event", "image.processed"),
        Message=json.dumps(payload, sort_keys=True),
    )
    return resp["MessageId"]


# ── Core processing ───────────────────────────────────────────────────

def process_image(image_id: str) -> dict:
    """Process one image end-to-end. Idempotent: already-PROCESSED records are skipped.

    Returns a summary dict with a ``status`` of ``PROCESSED``, ``FAILED`` or
    ``SKIPPED`` (plus a ``reason`` for the skipped/failed cases).
    """
    s3 = _client("s3")
    ddb = _client("dynamodb")
    sns = _client("sns")

    record = get_record(ddb, image_id)
    if record is None:
        logger.warning("image %s: no metadata record — nothing to process", image_id)
        return {"image_id": image_id, "status": "SKIPPED", "reason": "missing record"}
    if record.get("status") == "PROCESSED":
        logger.info("image %s: already PROCESSED — idempotent skip", image_id)
        return {"image_id": image_id, "status": "SKIPPED", "reason": "already processed"}

    original_key = record.get("original_key")
    if not original_key:
        return _fail(ddb, record, "missing original_key")


    try:
        obj = s3.get_object(Bucket=UPLOADS_BUCKET, Key=original_key)
        data = obj["Body"].read()
    except Exception as exc:  # noqa: BLE001 — any S3 failure → FAILED state
        logger.exception("image %s: could not read %s", image_id, original_key)
        return _fail(ddb, record, f"s3 read failed: {type(exc).__name__}")

    try:
        meta = extract_metadata(data)
        thumb = make_thumbnail(data)
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        logger.warning("image %s: not a decodable image (%s)", image_id, exc)
        return _fail(ddb, record, f"invalid image data: {type(exc).__name__}")

    filename = record.get("filename") or "image"
    thumbnail_key = f"thumbs/{image_id}/{filename}"
    s3.put_object(
        Bucket=THUMBS_BUCKET,
        Key=thumbnail_key,
        Body=thumb,
        ContentType=_MIME.get(meta["format"], "application/octet-stream"),
    )

    updated = _typed(record)
    updated.update(
        {
            "status": {"S": "PROCESSED"},
            "thumbnail_key": {"S": thumbnail_key},
            "processed_at": {"S": _now()},
            **{key: {"S": str(value)} for key, value in meta.items()},
        }
    )
    result = _put_record(ddb, updated)

    publish_event(
        sns,
        image_id,
        {
            "event": "image.processed",
            "image_id": image_id,
            "format": meta["format"],
            "width": meta["width"],
            "height": meta["height"],
            "thumbnail_key": thumbnail_key,
            "processed_at": result["processed_at"],
        },
    )
    logger.info(
        "image %s: PROCESSED (%s %sx%s)", image_id, meta["format"], meta["width"], meta["height"]
    )
    return {"image_id": image_id, "status": "PROCESSED", "thumbnail_key": thumbnail_key}


def _fail(ddb, record: dict, reason: str) -> dict:
    """Mark a record FAILED so it is observable instead of silently stuck PENDING."""
    updated = _typed(record)
    updated.update(
        {
            "status": {"S": "FAILED"},
            "error": {"S": reason},
            "processed_at": {"S": _now()},
        }
    )
    _put_record(ddb, updated)
    logger.error("image %s: FAILED — %s", record.get("image_id"), reason)
    return {"image_id": record.get("image_id"), "status": "FAILED", "reason": reason}


def process_pending(limit: int = 50) -> int:
    """Direct-mode trigger (``IMAGE_PROCESSING_TRIGGER=direct``): scan DynamoDB
    for PENDING records and process each. Returns how many became PROCESSED.

    Resilient by design: a failure on one image (logged) never aborts the rest
    of the batch. Note: records in ``FAILED`` status are not re-scanned — they
    are an observable dead-letter state by choice.
    """
    records = scan_pending(_client("dynamodb"), limit=limit)
    processed = 0
    for record in records:
        try:
            result = process_image(record["image_id"])
        except Exception as exc:  # noqa: BLE001 — keep the batch going
            logger.exception(
                "process_pending: image %s raised %s", record.get("image_id"), type(exc).__name__
            )
            continue
        if result.get("status") == "PROCESSED":
            processed += 1
    logger.info("process_pending: %d/%d PENDING images processed", processed, len(records))
    return processed


# ── AWS Lambda entry point (primary trigger: s3) ──────────────────────

def parse_s3_event(event: dict) -> list[str]:
    """Extract image_ids from an ``s3:ObjectCreated:*`` event.

    Keys live under ``uploads/<image_id>/<filename>``, so the image_id is the
    second path segment. Non-uploads keys are ignored (e.g. thumbs writes).
    """
    image_ids: list[str] = []
    for record in event.get("Records", []):
        key = ((record.get("s3") or {}).get("object") or {}).get("key", "")
        parts = key.split("/")
        if parts[:1] == ["uploads"] and len(parts) >= 2 and parts[1]:
            image_ids.append(parts[1])
    return image_ids


def lambda_handler(event: dict, context=None) -> dict:
    """AWS Lambda entry point — S3 event notification → process each image."""
    image_ids = parse_s3_event(event)
    results = [process_image(image_id) for image_id in image_ids]
    logger.info("lambda_handler: processed %d image(s): %s", len(results), results)
    return {"statusCode": 200, "processed": len(results), "results": results}
