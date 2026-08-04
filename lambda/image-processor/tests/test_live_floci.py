"""Live integration tests — the image-processor against the real local cloud (Floci :4566).

Skipped automatically when Floci is not running. Exercises the full
process step: S3 original → thumbnail → DynamoDB PROCESSED → SNS event.
"""
from __future__ import annotations

import base64
import socket
import sys
import uuid
from pathlib import Path

import boto3
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import handler  # noqa: E402

PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)


def _floci_reachable(host: str = "127.0.0.1", port: int = 4566) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


@pytest.fixture(scope="module")
def floci_up():
    if not _floci_reachable():
        pytest.skip("Floci not running on :4566")
    return True


@pytest.fixture(autouse=True)
def fresh_clients(monkeypatch):
    """Real boto3 clients (fresh, so earlier unit-test fakes can't leak in)."""
    monkeypatch.setattr(handler, "_clients", {})
    return None


def _ensure_cloud(s3, ddb, sns) -> None:
    for bucket in (handler.UPLOADS_BUCKET, handler.THUMBS_BUCKET):
        try:
            s3.head_bucket(Bucket=bucket)
        except Exception:
            s3.create_bucket(Bucket=bucket)
    if handler.METADATA_TABLE not in ddb.list_tables().get("TableNames", []):
        ddb.create_table(
            TableName=handler.METADATA_TABLE,
            KeySchema=[{"AttributeName": "image_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "image_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
    sns.create_topic(Name=handler.SNS_TOPIC)


def test_live_process_image_end_to_end(floci_up) -> None:
    s3 = boto3.client(
        "s3",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    ddb = boto3.client(
        "dynamodb",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    sns = boto3.client(
        "sns",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    _ensure_cloud(s3, ddb, sns)

    # NOTE: objects are placed under `test-only/` (NOT `uploads/`) so the live
    # S3→Lambda notification (filter_prefix=uploads/) does not race these tests.
    image_id = f"it-{uuid.uuid4()}"
    original_key = f"test-only/{image_id}/sample.png"
    thumb_key: str | None = None
    try:
        s3.put_object(
            Bucket=handler.UPLOADS_BUCKET, Key=original_key, Body=PNG_1X1, ContentType="image/png"
        )
        ddb.put_item(
            TableName=handler.METADATA_TABLE,
            Item={
                "image_id": {"S": image_id},
                "filename": {"S": "sample.png"},
                "content_type": {"S": "image/png"},
                "size": {"N": str(len(PNG_1X1))},
                "status": {"S": "PENDING"},
                "original_key": {"S": original_key},
                "uploaded_at": {"S": "2026-08-04T00:00:00+00:00"},
            },
        )

        result = handler.process_image(image_id)

        assert result["status"] == "PROCESSED", result

        # Thumbnail is physically in the thumbs bucket.
        thumb_key = result["thumbnail_key"]
        head = s3.head_object(Bucket=handler.THUMBS_BUCKET, Key=thumb_key)
        assert head["ContentLength"] > 0
        assert head["ContentType"] == "image/png"

        # Record updated with metadata.
        record = ddb.get_item(
            TableName=handler.METADATA_TABLE, Key={"image_id": {"S": image_id}}
        )["Item"]
        assert record["status"]["S"] == "PROCESSED"
        assert record["format"]["S"] == "PNG"
        assert record["width"]["S"] == "1"
        assert record["height"]["S"] == "1"
        assert len(record["sha256"]["S"]) == 64

        # Topic exists (event published).
        topics = {t["TopicArn"].rsplit(":", 1)[-1] for t in sns.list_topics()["Topics"]}
        assert handler.SNS_TOPIC in topics

        # Idempotent: re-processing skips.
        again = handler.process_image(image_id)
        assert again["status"] == "SKIPPED"
    finally:
        try:
            s3.delete_object(Bucket=handler.UPLOADS_BUCKET, Key=original_key)
        except Exception:
            pass
        if thumb_key:
            try:
                s3.delete_object(Bucket=handler.THUMBS_BUCKET, Key=thumb_key)
            except Exception:
                pass
        try:
            ddb.delete_item(TableName=handler.METADATA_TABLE, Key={"image_id": {"S": image_id}})
        except Exception:
            pass


def test_live_process_pending(floci_up) -> None:
    ddb = boto3.client(
        "dynamodb",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    s3 = boto3.client(
        "s3",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    sns = boto3.client(
        "sns",
        endpoint_url=handler.AWS_ENDPOINT_URL,
        region_name=handler.AWS_REGION,
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    _ensure_cloud(s3, ddb, sns)

    image_id = f"it-pending-{uuid.uuid4()}"
    original_key = f"test-only/{image_id}/sample.png"
    try:
        s3.put_object(
            Bucket=handler.UPLOADS_BUCKET, Key=original_key, Body=PNG_1X1, ContentType="image/png"
        )
        ddb.put_item(
            TableName=handler.METADATA_TABLE,
            Item={
                "image_id": {"S": image_id},
                "filename": {"S": "sample.png"},
                "content_type": {"S": "image/png"},
                "size": {"N": str(len(PNG_1X1))},
                "status": {"S": "PENDING"},
                "original_key": {"S": original_key},
                "uploaded_at": {"S": "2026-08-04T00:00:00+00:00"},
            },
        )

        assert handler.process_pending() >= 1

        record = ddb.get_item(
            TableName=handler.METADATA_TABLE, Key={"image_id": {"S": image_id}}
        )["Item"]
        assert record["status"]["S"] == "PROCESSED"
    finally:
        try:
            s3.delete_object(Bucket=handler.UPLOADS_BUCKET, Key=original_key)
        except Exception:
            pass
        ddb.delete_item(TableName=handler.METADATA_TABLE, Key={"image_id": {"S": image_id}})
