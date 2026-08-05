"""S3 storage service.

All clients declare the Floci endpoint explicitly (AGENTS.md §2) — the app
never relies on ambient real-cloud configuration. Credentials come from
resolve_aws_credentials() (Phase 14): Secrets Manager when IMAGEFLOW_SECRET_NAME
is set, otherwise env/settings.
"""
from __future__ import annotations

import boto3

from app.config.settings import get_settings
from app.services.secrets import resolve_aws_credentials


def get_s3_client():
    """S3 client pointed at the local cloud (Floci)."""
    settings = get_settings()
    access_key, secret_key = resolve_aws_credentials()
    return boto3.client(
        "s3",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )


def ensure_buckets(client) -> None:
    """Create the upload/thumbs buckets if they do not exist yet."""
    settings = get_settings()
    for bucket in (settings.uploads_bucket, settings.thumbs_bucket):
        try:
            client.head_bucket(Bucket=bucket)
        except Exception:
            client.create_bucket(Bucket=bucket)


def upload_original(client, image_id: str, filename: str, data: bytes, content_type: str) -> str:
    """Store the original image and return its S3 key."""
    settings = get_settings()
    key = f"uploads/{image_id}/{filename}"
    client.put_object(
        Bucket=settings.uploads_bucket,
        Key=key,
        Body=data,
        ContentType=content_type,
    )
    return key


def presigned_url(client, bucket: str, key: str, expires: int = 3600) -> str:
    """Time-limited download URL for an S3 object."""
    return client.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=expires,
    )
