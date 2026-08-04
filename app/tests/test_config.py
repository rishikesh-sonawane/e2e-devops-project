"""Unit tests for the configuration module — secret safety + env overrides."""
import os
from unittest.mock import patch

import pytest

from app.config.settings import Settings, get_settings


@pytest.fixture(autouse=True)
def clean_env():
    """Hermetic env for every config test — ambient vars (e.g. `eval $(floci env)`)
    must never leak into assertions about defaults."""
    with patch.dict(os.environ, {}, clear=True):
        yield


def test_defaults_match_floci_contract() -> None:
    s = Settings()
    assert s.app_name == "imageflow"
    assert s.aws_endpoint_url == "http://localhost:4566"
    assert s.aws_region == "us-east-1"
    assert s.image_processing_trigger == "s3"


def test_env_override_wins() -> None:
    with patch.dict(os.environ, {"IMAGE_PROCESSING_TRIGGER": "direct"}, clear=False):
        s = Settings()
        assert s.image_processing_trigger == "direct"


def test_safe_config_masks_secrets() -> None:
    s = Settings()
    cfg = s.safe_config()
    assert cfg["aws_access_key_id"] == "***"
    assert cfg["aws_secret_access_key"] == "***"
    # Non-secret values pass through untouched
    assert cfg["aws_endpoint_url"] == "http://localhost:4566"
    assert cfg["image_processing_trigger"] == "s3"
    # The raw secret ('test') never appears in any non-masked value
    assert all("test" not in v for v in cfg.values())


def test_model_dump_redacts_secrets() -> None:
    """SecretStr auto-redaction — even a raw model_dump cannot leak.

    Note: model_dump(mode='python') returns SecretStr objects for secret
    fields; their str() form is the redacted '**********', and the real
    value is only reachable via an explicit .get_secret_value() call.
    """
    s = Settings()
    dumped = s.model_dump()
    assert str(dumped["aws_secret_access_key"]) == "**********"
    assert str(dumped["aws_access_key_id"]) == "**********"
    # Redaction is not cosmetic: get_secret_value() is the ONLY reveal path
    assert dumped["aws_secret_access_key"].get_secret_value() == "test"


def test_get_settings_is_singleton() -> None:
    assert get_settings() is get_settings()
