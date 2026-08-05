"""DynamoDB metadata service — the fast catalogue for every uploaded image."""
from __future__ import annotations

from datetime import UTC, datetime

import boto3

from app.config.settings import get_settings
from app.services.secrets import resolve_aws_credentials


def get_ddb_client():
    """DynamoDB client pointed at the local cloud (Floci)."""
    settings = get_settings()
    access_key, secret_key = resolve_aws_credentials()
    return boto3.client(
        "dynamodb",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )


def ensure_table(client) -> None:
    """Create the metadata table if it does not exist yet."""
    settings = get_settings()
    if settings.metadata_table not in client.list_tables().get("TableNames", []):
        client.create_table(
            TableName=settings.metadata_table,
            KeySchema=[{"AttributeName": "image_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "image_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )


def create_record(
    client,
    image_id: str,
    *,
    filename: str,
    content_type: str,
    size: int,
    original_key: str,
) -> dict:
    """Write a PENDING record for a newly uploaded image."""
    settings = get_settings()
    item = {
        "image_id": {"S": image_id},
        "filename": {"S": filename},
        "content_type": {"S": content_type},
        "size": {"N": str(size)},
        "status": {"S": "PENDING"},
        "original_key": {"S": original_key},
        "uploaded_at": {"S": datetime.now(UTC).isoformat()},
    }
    client.put_item(TableName=settings.metadata_table, Item=item)
    return _deserialize(item)


def get_record(client, image_id: str) -> dict | None:
    """Fetch one record, or None when it does not exist."""
    settings = get_settings()
    resp = client.get_item(TableName=settings.metadata_table, Key={"image_id": {"S": image_id}})
    item = resp.get("Item")
    return _deserialize(item) if item else None


def delete_record(client, image_id: str) -> None:
    """Remove one record (rollback for a failed upload — see images.py)."""
    settings = get_settings()
    client.delete_item(TableName=settings.metadata_table, Key={"image_id": {"S": image_id}})


def list_records(client, limit: int = 20, last_image_id: str | None = None) -> dict:
    """Scan the catalogue with cursor pagination."""
    settings = get_settings()
    params: dict = {"TableName": settings.metadata_table, "Limit": limit}
    if last_image_id:
        params["ExclusiveStartKey"] = {"image_id": {"S": last_image_id}}
    resp = client.scan(**params)
    items = [_deserialize(item) for item in resp.get("Items", [])]
    last = resp.get("LastEvaluatedKey")
    return {"items": items, "next": last["image_id"]["S"] if last else None}


def _deserialize(item: dict) -> dict:
    """Convert DynamoDB's typed map to a plain dict of values."""
    return {key: next(iter(values.values())) for key, values in item.items()}
