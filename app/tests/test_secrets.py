"""Unit tests for the secrets & encryption service (Phase 14, ADR-12).

Covers: SecretString round trip, missing-secret None, KMS encrypt/decrypt
round trip + ciphertext opacity, and the credential-resolution order
(secret wins over settings; failures degrade to settings).
"""
from unittest.mock import patch

import pytest

from app.services import secrets
from app.tests.fakes import FakeKMS, FakeSecretsManager


@pytest.fixture(autouse=True)
def fakes(monkeypatch):
    sm = FakeSecretsManager()
    kms = FakeKMS()
    monkeypatch.setattr(secrets, "get_secrets_manager_client", lambda: sm)
    monkeypatch.setattr(secrets, "get_kms_client", lambda: kms)
    return sm, kms


# ── Secrets Manager ──────────────────────────────────────────────────

def test_put_then_fetch_secret_round_trip(fakes) -> None:
    sm, _ = fakes
    arn = secrets.put_secret("imageflow/api", {"token": "s3cr3t", "env": "dev"})
    assert "imageflow/api" in arn
    assert secrets.fetch_secret("imageflow/api") == {"token": "s3cr3t", "env": "dev"}


def test_put_secret_upserts_existing(fakes) -> None:
    sm, _ = fakes
    secrets.put_secret("imageflow/api", {"token": "v1"})
    secrets.put_secret("imageflow/api", {"token": "v2"})  # must not raise
    assert secrets.fetch_secret("imageflow/api") == {"token": "v2"}


def test_fetch_missing_secret_returns_none(fakes) -> None:
    assert secrets.fetch_secret("does/not/exist") is None


# ── KMS ──────────────────────────────────────────────────────────────

def test_kms_round_trip_recovers_plaintext(fakes) -> None:
    _, kms = fakes
    key = kms.create_key()["KeyMetadata"]["KeyId"]
    ciphertext = secrets.kms_encrypt(key, "top-secret-value")
    assert ciphertext != "top-secret-value"  # ciphertext is opaque
    assert secrets.kms_decrypt(key, ciphertext) == "top-secret-value"


def test_kms_ciphertext_is_not_plaintext(fakes) -> None:
    _, kms = fakes
    key = kms.create_key()["KeyMetadata"]["KeyId"]
    ciphertext = secrets.kms_encrypt(key, "password123")
    assert "password123" not in ciphertext


# ── Credential resolution ────────────────────────────────────────────

def test_resolve_prefers_secret_when_configured(fakes, monkeypatch) -> None:
    sm, _ = fakes
    secrets.put_secret(
        "imageflow/aws-creds", {"AWS_ACCESS_KEY_ID": "from-secret", "AWS_SECRET_ACCESS_KEY": "k"}
    )
    monkeypatch.setattr(secrets.get_settings(), "secret_name", "imageflow/aws-creds")
    assert secrets.resolve_aws_credentials() == ("from-secret", "k")


def test_resolve_falls_back_to_settings_without_secret(fakes, monkeypatch) -> None:
    monkeypatch.setattr(secrets.get_settings(), "secret_name", "")
    assert secrets.resolve_aws_credentials() == ("test", "test")


def test_resolve_degrades_when_secret_store_unreachable(fakes, monkeypatch) -> None:
    monkeypatch.setattr(secrets.get_settings(), "secret_name", "imageflow/aws-creds")

    def _boom(*args, **kwargs):
        raise RuntimeError("secrets manager down")

    monkeypatch.setattr(secrets, "get_secrets_manager_client", _boom)
    # Must not raise — degrades to settings (ADR-12).
    assert secrets.resolve_aws_credentials() == ("test", "test")


def test_resolve_ignores_secret_missing_cred_keys(fakes, monkeypatch) -> None:
    secrets.put_secret("imageflow/bad-secret", {"token": "nope"})
    monkeypatch.setattr(secrets.get_settings(), "secret_name", "imageflow/bad-secret")
    assert secrets.resolve_aws_credentials() == ("test", "test")


def test_storage_client_uses_resolved_credentials(monkeypatch) -> None:
    """The S3 factory must consume the resolved credentials (integration)."""
    captured: dict = {}
    import app.services.storage as storage

    def _fake_boto3_client(service, **kwargs):
        captured.update(kwargs)
        return object()

    monkeypatch.setattr(secrets.get_settings(), "secret_name", "")
    monkeypatch.setattr("app.services.storage.boto3.client", _fake_boto3_client)
    with patch("app.services.storage.resolve_aws_credentials", return_value=("ak", "sk")):
        storage.get_s3_client()
    assert captured["aws_access_key_id"] == "ak"
    assert captured["aws_secret_access_key"] == "sk"
