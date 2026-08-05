"""In-memory fake AWS clients — keep unit tests fast, deterministic, offline."""


class FakeS3:
    def __init__(self) -> None:
        self.buckets: set[str] = set()
        self.objects: dict[str, dict[str, dict]] = {}

    def head_bucket(self, **kwargs) -> None:
        if kwargs["Bucket"] not in self.buckets:
            raise Exception("bucket not found")

    def create_bucket(self, **kwargs) -> None:
        self.buckets.add(kwargs["Bucket"])

    def put_object(self, **kwargs) -> None:
        bucket = kwargs.pop("Bucket")
        key = kwargs.pop("Key")
        self.objects.setdefault(bucket, {})[key] = kwargs

    def generate_presigned_url(self, method: str, Params: dict, ExpiresIn: int = 3600) -> str:
        return f"https://presigned/{Params['Bucket']}/{Params['Key']}?expires={ExpiresIn}"


class FakeCloudWatch:
    """Captures CloudWatch calls (Phase 13 metrics + logs)."""

    def __init__(self) -> None:
        self.datapoints: list[dict] = []
        self.log_events: list[dict] = []

    def put_metric_data(self, **kwargs) -> dict:
        self.datapoints.append(kwargs)
        return {}

    def create_log_group(self, **kwargs) -> None:
        self.log_groups = getattr(self, "log_groups", set()) | {kwargs["logGroupName"]}

    def create_log_stream(self, **kwargs) -> None:
        self.log_streams = getattr(self, "log_streams", set()) | {kwargs["logStreamName"]}

    def put_log_events(self, **kwargs) -> dict:
        self.log_events.append(kwargs)
        return {"nextSequenceToken": "tok-1"}


class FakeSecretsManager:
    """In-memory Secrets Manager (Phase 14): create_secret + get_secret_value."""

    class exceptions:
        class ResourceNotFoundException(Exception):
            pass

        class ResourceExistsException(Exception):
            pass

    def __init__(self) -> None:
        self.secrets: dict[str, str] = {}

    def create_secret(self, **kwargs) -> dict:
        name = kwargs["Name"]
        if name in self.secrets:
            raise self.exceptions.ResourceExistsException(name)
        self.secrets[name] = kwargs.get("SecretString", "")
        return {"ARN": f"arn:aws:secretsmanager:us-east-1:000000000000:secret:{name}"}

    def update_secret(self, **kwargs) -> dict:
        name = kwargs["SecretId"]
        self.secrets[name] = kwargs.get("SecretString", "")
        return {"ARN": f"arn:aws:secretsmanager:us-east-1:000000000000:secret:{name}"}

    def get_secret_value(self, **kwargs) -> dict:
        name = kwargs["SecretId"]
        if name not in self.secrets:
            raise self.exceptions.ResourceNotFoundException(name)
        return {"SecretString": self.secrets[name]}


class FakeKMS:
    """In-memory KMS (Phase 14): reversible encrypt/decrypt via base64.

    Not real crypto — the tests only prove the round trip + boto3 call shape.
    """

    def __init__(self) -> None:
        self.keys: set[str] = set()

    def create_key(self, **kwargs) -> dict:
        key_id = f"key-{len(self.keys) + 1}"
        self.keys.add(key_id)
        arn = f"arn:aws:kms:us-east-1:000000000000:key/{key_id}"
        return {"KeyMetadata": {"KeyId": key_id, "Arn": arn}}

    def encrypt(self, **kwargs) -> dict:
        import base64

        blob = base64.b64encode(kwargs["Plaintext"])
        return {"CiphertextBlob": blob}

    def decrypt(self, **kwargs) -> dict:
        import base64

        return {"Plaintext": base64.b64decode(kwargs["CiphertextBlob"])}


class FakeDDB:
    def __init__(self) -> None:
        self.tables: set[str] = set()
        self.items: dict[str, dict[str, dict]] = {}

    def list_tables(self) -> dict:
        return {"TableNames": sorted(self.tables)}

    def create_table(self, **kwargs) -> None:
        self.tables.add(kwargs["TableName"])

    def put_item(self, **kwargs) -> None:
        table = kwargs["TableName"]
        item = kwargs["Item"]
        self.items.setdefault(table, {})[item["image_id"]["S"]] = item

    def delete_item(self, **kwargs) -> None:
        table = kwargs["TableName"]
        key = kwargs["Key"]["image_id"]["S"]
        self.items.get(table, {}).pop(key, None)

    def get_item(self, **kwargs) -> dict:
        table = kwargs["TableName"]
        key = kwargs["Key"]["image_id"]["S"]
        item = self.items.get(table, {}).get(key)
        return {"Item": item} if item else {}

    def scan(self, **kwargs) -> dict:
        table = kwargs["TableName"]
        limit = kwargs.get("Limit", 20)
        items = list(self.items.get(table, {}).values())

        start = kwargs.get("ExclusiveStartKey")
        if start:
            start_id = start["image_id"]["S"]
            for i, item in enumerate(items):
                if item["image_id"]["S"] == start_id:
                    items = items[i + 1 :]
                    break
            else:
                items = []

        page = items[:limit]
        has_more = len(items) > limit
        return {
            "Items": page,
            "LastEvaluatedKey": (
                {"image_id": {"S": page[-1]["image_id"]["S"]}} if has_more else None
            ),
        }
