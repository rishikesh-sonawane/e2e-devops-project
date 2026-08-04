"""Application configuration — env-var driven, zero hardcoded secrets.

Every value can be overridden with an environment variable (e.g.
AWS_ENDPOINT_URL, IMAGE_PROCESSING_TRIGGER). See docs/architecture.md §4.2.
"""
from __future__ import annotations

from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration for the ImageFlow API."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ── App ────────────────────────────────────────────────────
    app_name: str = "imageflow"
    app_version: str = "0.1.0"
    environment: str = "development"

    # ── Runtime ────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"

    # ── Build metadata (injected at build time; git fallback in main.py) ──
    git_sha: str = ""
    build_timestamp: str = ""

    # ── AWS / Floci (dummy credentials are fine — ADR-02) ───────
    aws_region: str = "us-east-1"
    aws_endpoint_url: str = "http://localhost:4566"
    # SecretStr: pydantic auto-redacts these in every dump — they can never
    # leak through /config, logs, or serialization (AGENTS.md §3.5).
    aws_access_key_id: SecretStr = SecretStr("test")
    aws_secret_access_key: SecretStr = SecretStr("test")

    # ── ImageFlow pipeline ─────────────────────────────────────
    uploads_bucket: str = "imageflow-uploads"
    thumbs_bucket: str = "imageflow-thumbs"
    metadata_table: str = "ImageFlowMetadata"
    sns_topic: str = "imageflow-events"
    image_processing_trigger: str = "s3"  # s3 | dynamodb | direct (ADR-07)

    def safe_config(self) -> dict[str, str]:
        """Non-secret config dump for the `/config` endpoint.

        Credentials are typed ``SecretStr`` so they are auto-redacted in
        every dump — never exposed (AGENTS.md §3.5).
        """
        out: dict[str, str] = {}
        for name, value in self.model_dump().items():
            if isinstance(value, SecretStr) or value == "**********":
                out[name] = "***"
            else:
                out[name] = str(value)
        return out


@lru_cache
def get_settings() -> Settings:
    """Singleton accessor — config is read once and cached per process."""
    return Settings()
