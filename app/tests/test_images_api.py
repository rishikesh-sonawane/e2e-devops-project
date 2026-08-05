"""Unit tests for the image pipeline endpoints (S3 + DynamoDB via fakes)."""
import base64
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.tests.fakes import FakeCloudWatch, FakeDDB, FakeS3

client = TestClient(app)

# A real 1x1 PNG so uploads carry valid image bytes.
PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)


@pytest.fixture(autouse=True)
def fake_cloud():
    fake_s3 = FakeS3()
    fake_ddb = FakeDDB()
    fake_cw = FakeCloudWatch()
    with patch("app.services.storage.get_s3_client", return_value=fake_s3), patch(
        "app.services.metadata.get_ddb_client", return_value=fake_ddb
    ), patch(
        "app.services.observability.get_cloudwatch_client", return_value=fake_cw
    ):
        yield fake_s3, fake_ddb, fake_cw


def test_upload_creates_pending_record(fake_cloud) -> None:
    fake_s3, fake_ddb, _cw = fake_cloud
    resp = client.post(
        "/api/v1/images", files={"file": ("photo.png", PNG_1X1, "image/png")}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "PENDING"
    assert body["filename"] == "photo.png"
    assert body["content_type"] == "image/png"
    assert int(body["size"]) == len(PNG_1X1)
    # Bytes landed in the fake S3 warehouse under uploads/<id>/photo.png
    assert any(
        "uploads/" in key and key.endswith("photo.png")
        for key in fake_s3.objects.get("imageflow-uploads", {})
    )


def test_upload_empty_file_rejected(fake_cloud) -> None:
    resp = client.post("/api/v1/images", files={"file": ("empty.png", b"", "image/png")})
    assert resp.status_code == 400


def test_get_image_returns_presigned_url(fake_cloud) -> None:
    created = client.post(
        "/api/v1/images", files={"file": ("photo.png", PNG_1X1, "image/png")}
    ).json()
    resp = client.get(f"/api/v1/images/{created['image_id']}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["original_url"].startswith("https://presigned/imageflow-uploads/")
    assert body["status"] == "PENDING"


def test_get_missing_image_404(fake_cloud) -> None:
    resp = client.get("/api/v1/images/does-not-exist")
    assert resp.status_code == 404


def test_list_images_paginated(fake_cloud) -> None:
    for i in range(3):
        client.post("/api/v1/images", files={"file": (f"img{i}.png", PNG_1X1, "image/png")})

    first = client.get("/api/v1/images", params={"limit": 2}).json()
    assert len(first["items"]) == 2
    assert first["next"]  # cursor present when more items remain

    second = client.get("/api/v1/images", params={"limit": 2, "cursor": first["next"]}).json()
    assert len(second["items"]) == 1
    assert second["next"] is None


def test_upload_sanitizes_filename(fake_cloud) -> None:
    resp = client.post(
        "/api/v1/images",
        files={"file": ("../../etc/passwd.png", PNG_1X1, "image/png")},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["filename"] == "passwd.png"  # path components stripped
    assert "/.." not in body["original_key"]


def test_upload_too_large_rejected(fake_cloud) -> None:
    big = b"x" * (10 * 1024 * 1024 + 1)
    resp = client.post("/api/v1/images", files={"file": ("big.png", big, "image/png")})
    assert resp.status_code == 413
