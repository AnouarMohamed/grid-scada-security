from __future__ import annotations

import pytest
from gridguard_fake_telemetry.config import IngestConfig, SourceConfig


def test_source_config_rejects_out_of_range_port(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_SOURCE_PORT", "70000")

    with pytest.raises(ValueError, match="GRIDGUARD_SOURCE_PORT"):
        SourceConfig.from_env()


def test_ingest_config_rejects_nonpositive_interval(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_INGEST_INTERVAL_SECONDS", "0")

    with pytest.raises(ValueError, match="GRIDGUARD_INGEST_INTERVAL_SECONDS"):
        IngestConfig.from_env()


def test_ingest_config_rejects_nonpositive_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_REQUEST_TIMEOUT_SECONDS", "-1")

    with pytest.raises(ValueError, match="GRIDGUARD_REQUEST_TIMEOUT_SECONDS"):
        IngestConfig.from_env()
