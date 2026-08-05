"""Secrets & encryption service — Phase 14 (Security hardening, ADR-12).

Two responsibilities:

1. **Secrets Manager** — fetch/put application secrets (JSON SecretString).
   The API can source its AWS credentials from a secret instead of env vars
   (``IMAGEFLOW_SECRET_NAME``) — the classic production pattern for rotating
   credentials without redeploys. Fetch failures fall back to settings and
   log a warning; the pipeline never dies because a secret is unreachable.

2. **KMS** — symmetric-key encrypt/decrypt round trip. The demo script uses
   this to prove that the ciphertext stored anywhere is opaque without the
   key (``kms_encrypt`` / ``kms_decrypt``).

Security posture (AGENTS.md §3.5): nothing secret is ever logged or echoed —
the demo script shows only masked confirmations and opaque ciphertext.
"""
from __future__ import annotations

import base64
import json
import logging
from typing import Any

import boto3

from app.config.settings import get_settings

logger = logging.getLogger("imageflow.secrets")

# Name of the Secrets Manager secret that can hold the API's AWS credentials
# (JSON: {"AWS_ACCESS_KEY_ID": ..., "AWS_SECRET_ACCESS_KEY": ...}).
CREDENTIAL_SECRET_ENV = "IMAGEFLOW_SECRET_NAME"


# ── Clients (explicit Floci endpoint, AGENTS.md §2) ──────────────────
def get_secrets_manager_client():
    settings = get_settings()
    return boto3.client(
        "secretsmanager",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id.get_secret_value(),
        aws_secret_access_key=settings.aws_secret_access_key.get_secret_value(),
    )


def get_kms_client():
    settings = get_settings()
    return boto3.client(
        "kms",
        endpoint_url=settings.aws_endpoint_url,
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id.get_secret_value(),
        aws_secret_access_key=settings.aws_secret_access_key.get_secret_value(),
    )


# ── Secrets Manager ──────────────────────────────────────────────────
def fetch_secret(name: str, client=None) -> dict[str, Any] | None:
    """Read a JSON SecretString. Returns None when the secret does not exist."""
    client = client or get_secrets_manager_client()
    try:
        resp = client.get_secret_value(SecretId=name)
    except client.exceptions.ResourceNotFoundException:
        return None
    return json.loads(resp["SecretString"])


def put_secret(name: str, value: dict[str, Any], client=None, description: str = "") -> str:
    """Upsert a JSON secret (create, or update if it exists); returns the ARN."""
    client = client or get_secrets_manager_client()
    payload = json.dumps(value, sort_keys=True)
    try:
        resp = client.create_secret(Name=name, SecretString=payload, Description=description)
    except client.exceptions.ResourceExistsException:
        resp = client.update_secret(SecretId=name, SecretString=payload, Description=description)
    return resp["ARN"]


# ── KMS ──────────────────────────────────────────────────────────────
def kms_encrypt(key_id: str, plaintext: str, client=None) -> str:
    """Encrypt a string with a KMS symmetric key; returns base64 ciphertext."""
    client = client or get_kms_client()
    resp = client.encrypt(KeyId=key_id, Plaintext=plaintext.encode("utf-8"))
    return base64.b64encode(resp["CiphertextBlob"]).decode("ascii")


def kms_decrypt(key_id: str, ciphertext_b64: str, client=None) -> str:
    """Decrypt base64 ciphertext back to the plaintext string."""
    client = client or get_kms_client()
    resp = client.decrypt(
        KeyId=key_id,
        CiphertextBlob=base64.b64decode(ciphertext_b64.encode("ascii")),
    )
    return resp["Plaintext"].decode("utf-8")


# ── Credential resolution (secrets-backed AWS creds) ─────────────────
def resolve_aws_credentials() -> tuple[str, str]:
    """AWS credentials for this process.

    Order: secrets-backed secret (``IMAGEFLOW_SECRET_NAME``) → env/settings.
    Always returns a usable pair — a secret-store failure degrades to the
    settings fallback with a warning; the pipeline must never die because a
    secret store is unreachable (ADR-12).
    """
    settings = get_settings()
    secret_name = settings.secret_name
    if secret_name:
        try:
            secret = fetch_secret(secret_name)
            if secret and secret.get("AWS_ACCESS_KEY_ID") and secret.get("AWS_SECRET_ACCESS_KEY"):
                logger.info("aws credentials resolved from Secrets Manager (%s)", secret_name)
                return secret["AWS_ACCESS_KEY_ID"], secret["AWS_SECRET_ACCESS_KEY"]
            logger.warning(
                "secret %s exists but lacks AWS credential keys — using settings", secret_name
            )
        except Exception as exc:  # noqa: BLE001 — degrade, never break
            logger.warning("could not read secret %s (%s) — using settings", secret_name, exc)
    return (
        settings.aws_access_key_id.get_secret_value(),
        settings.aws_secret_access_key.get_secret_value(),
    )
