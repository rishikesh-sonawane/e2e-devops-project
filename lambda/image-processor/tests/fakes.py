"""In-memory fake AWS clients for image-processor unit tests (offline, fast).

Kept separate from ``app/tests/fakes.py`` because the Lambda is a standalone
deployable unit that must never import from ``app/``.
"""
from __future__ import annotations

from io import BytesIO


class FakeS3:
    def __init__(self) -> None:
        self.objects: dict[str, dict[str, dict]] = {}

    def get_object(self, **kwargs) -> dict:
        bucket = kwargs["Bucket"]
        key = kwargs["Key"]
        try:
            body = self.objects[bucket][key]["Body"]
        except KeyError as exc:
            raise Exception(f"no such object: {bucket}/{key}") from exc
        return {"Body": BytesIO(body)}

    def put_object(self, **kwargs) -> None:
        bucket = kwargs.pop("Bucket")
        key = kwargs.pop("Key")
        self.objects.setdefault(bucket, {})[key] = dict(kwargs)


class FakeDDB:
    def __init__(self) -> None:
        self.items: dict[str, dict[str, dict]] = {}

    def get_item(self, **kwargs) -> dict:
        image_id = kwargs["Key"]["image_id"]["S"]
        item = self.items.get(image_id)
        return {"Item": item} if item else {}

    def put_item(self, **kwargs) -> None:
        item = kwargs["Item"]
        self.items[item["image_id"]["S"]] = item

    def scan(self, **kwargs) -> dict:
        items = list(self.items.values())
        if "FilterExpression" in kwargs and kwargs.get("ExpressionAttributeValues"):
            want = kwargs["ExpressionAttributeValues"][":pending"]["S"]
            items = [item for item in items if item.get("status", {}).get("S") == want]
        return {"Items": items}


class FakeSNS:
    def __init__(self) -> None:
        self.topics: set[str] = set()
        self.published: list[dict] = []

    def create_topic(self, **kwargs) -> dict:
        name = kwargs["Name"]
        self.topics.add(name)
        return {"TopicArn": f"arn:aws:sns:us-east-1:000000000000:{name}"}

    def publish(self, **kwargs) -> dict:
        self.published.append(kwargs)
        return {"MessageId": f"msg-{len(self.published)}"}


class FakeCloudWatch:
    """Captures put_metric_data calls for the Phase 13 metric-emission tests."""

    def __init__(self) -> None:
        self.datapoints: list[dict] = []

    def put_metric_data(self, **kwargs) -> dict:
        self.datapoints.append(kwargs)
        return {}
