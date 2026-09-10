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


def test_config_accepts_scenario_replay_metadata(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_SCENARIO", "naive-bad-value")
    monkeypatch.setenv("GRIDGUARD_ATTACK_FLAG", "1")

    config = AppConfig.from_env()

    assert config.scenario_override == "naive-bad-value"
    assert config.attack_flag_override == 1


def test_config_rejects_invalid_attack_flag(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GRIDGUARD_ATTACK_FLAG", "2")

    with pytest.raises(ValueError, match="GRIDGUARD_ATTACK_FLAG"):
        AppConfig.from_env()
