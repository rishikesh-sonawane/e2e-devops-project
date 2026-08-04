"""Live integration tests — run against the real local cloud (Floci :4566).

Skipped automatically when Floci is not running. In CI (Phase 8) this runs
inside the floci service container.
"""
import base64
import socket

import pytest
from fastapi.testclient import TestClient

from app.main import app

PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)


def _floci_reachable(host: str = "127.0.0.1", port: int = 4566) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session")
def floci_up():
    """Skip at fixture time (not import time) so CI's service container has a
    chance to become ready before the check runs."""
    if not _floci_reachable():
        pytest.skip("Floci not running on :4566")
    return True


def test_live_upload_get_list(floci_up) -> None:
    client = TestClient(app)

    created = client.post(
        "/api/v1/images", files={"file": ("hello.png", PNG_1X1, "image/png")}
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["status"] == "PENDING"
    image_id = body["image_id"]

    fetched = client.get(f"/api/v1/images/{image_id}")
    assert fetched.status_code == 200
    assert fetched.json()["original_url"].startswith("http")

    # The table may contain pre-existing records (dev demos), so page through
    # the listing until the new image is found (or the pages run out).
    found = False
    cursor = None
    for _ in range(10):
        params = {"cursor": cursor} if cursor else {}
        listing = client.get("/api/v1/images", params=params)
        assert listing.status_code == 200
        page = listing.json()
        if any(item["image_id"] == image_id for item in page["items"]):
            found = True
            break
        cursor = page.get("next")
        if not cursor:
            break
    assert found, "uploaded image not found in paginated listing"
