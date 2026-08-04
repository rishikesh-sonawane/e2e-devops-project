"""Image pipeline routes — upload → S3 + DynamoDB (PENDING record)."""
from __future__ import annotations

import logging
import uuid
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.config.settings import get_settings
from app.services import metadata, storage

logger = logging.getLogger("imageflow")

router = APIRouter(prefix="/api/v1/images", tags=["images"])

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MiB

_buckets_ready = False


def _ensure_cloud() -> None:
    """One-time lazy provisioning of buckets + table (later replaced by Terraform)."""
    global _buckets_ready
    if not _buckets_ready:
        storage.ensure_buckets(storage.get_s3_client())
        metadata.ensure_table(metadata.get_ddb_client())
        _buckets_ready = True


def _cloud_unavailable() -> HTTPException:
    """Log the real error server-side; never leak internals to the client."""
    logger.exception("cloud operation failed")
    return HTTPException(status_code=503, detail="cloud unavailable")


@router.post("", status_code=201, summary="Upload an image (→ S3 + DynamoDB)")
async def upload_image(file: UploadFile = File(...)) -> dict:  # noqa: B008 — FastAPI dependency-injection pattern
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="file too large (max 10 MiB)")

    # Sanitize the user-supplied filename: strip any path components so a
    # crafted name (e.g. "../../x") can never alter the S3 key structure.
    filename = Path(file.filename or "").name
    if not filename:
        raise HTTPException(status_code=400, detail="filename required")
    if len(filename.encode("utf-8")) > 255:
        raise HTTPException(status_code=400, detail="filename too long")

    image_id = str(uuid.uuid4())
    content_type = file.content_type or "application/octet-stream"

    try:
        _ensure_cloud()
        s3 = storage.get_s3_client()
        ddb = metadata.get_ddb_client()
        original_key = storage.upload_original(s3, image_id, filename, data, content_type)
        return metadata.create_record(
            ddb,
            image_id,
            filename=filename,
            content_type=content_type,
            size=len(data),
            original_key=original_key,
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise _cloud_unavailable() from exc


@router.get("/{image_id}", summary="Get image metadata + download URLs")
def get_image(image_id: str) -> dict:
    try:
        record = metadata.get_record(metadata.get_ddb_client(), image_id)
    except Exception as exc:
        raise _cloud_unavailable() from exc

    if record is None:
        raise HTTPException(status_code=404, detail="image not found")

    settings = get_settings()
    try:
        s3 = storage.get_s3_client()
        record["original_url"] = storage.presigned_url(
            s3, settings.uploads_bucket, record["original_key"]
        )
        if record.get("status") == "PROCESSED" and record.get("thumbnail_key"):
            record["thumbnail_url"] = storage.presigned_url(
                s3, settings.thumbs_bucket, record["thumbnail_key"]
            )
    except Exception as exc:
        raise _cloud_unavailable() from exc
    return record


@router.get("", summary="List images (paginated)")
def list_images(limit: int = 20, cursor: str | None = None) -> dict:
    limit = max(1, min(limit, 100))
    try:
        return metadata.list_records(metadata.get_ddb_client(), limit=limit, last_image_id=cursor)
    except Exception as exc:
        raise _cloud_unavailable() from exc
