from __future__ import annotations

import pytest
from gridguard_modbus_ingestor.config import AppConfig


def test_config_rejects_invalid_mode(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_MODBUS_MODE", "serial")

    with pytest.raises(ValueError, match="GRIDGUARD_MODBUS_MODE"):
        AppConfig.from_env()


def test_config_rejects_invalid_unit_id(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_MODBUS_UNIT_ID", "248")

    with pytest.raises(ValueError, match="GRIDGUARD_MODBUS_UNIT_ID"):
        AppConfig.from_env()


def test_config_uses_register_map_unit_id_by_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("GRIDGUARD_MODBUS_UNIT_ID", raising=False)

    assert AppConfig.from_env().modbus_unit_id is None


def test_config_rejects_nonpositive_interval(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_MODBUS_INGEST_INTERVAL_SECONDS", "0")

    with pytest.raises(ValueError, match="GRIDGUARD_MODBUS_INGEST_INTERVAL_SECONDS"):
        AppConfig.from_env()
