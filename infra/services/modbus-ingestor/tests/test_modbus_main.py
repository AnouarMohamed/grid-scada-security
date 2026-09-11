from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import gridguard_modbus_ingestor.main as app
import pytest
from gridguard_modbus_ingestor.clients import FixtureRegisterClient, ModbusTcpClient
from gridguard_modbus_ingestor.config import AppConfig

ROOT = Path(__file__).resolve().parents[3]
REGISTER_MAP = ROOT / "contracts/register-maps/ieee13-demo.json"
FIXTURE = ROOT / "contracts/register-maps/fixtures/ieee13-baseline-registers.json"


def build_config(tmp_path: Path) -> AppConfig:
    return AppConfig(
        mode="fixture",
        register_map=REGISTER_MAP,
        register_fixture=FIXTURE,
        source_id="modbus_fixture",
        modbus_host="power-sim",
        modbus_port=502,
        modbus_unit_id=1,
        scenario_override=None,
        attack_flag_override=None,
        interval_seconds=2.0,
        request_timeout_seconds=5.0,
        status_file=tmp_path / "ready",
        influx_url="http://influxdb:8086",
        influx_org="gridguard",
        influx_bucket="telemetry",
        influx_token="test-token",
    )


def test_build_client_selects_fixture_or_tcp(tmp_path: Path) -> None:
    config = build_config(tmp_path)
    assert isinstance(app.build_client(config), FixtureRegisterClient)
    assert isinstance(app.build_client(replace(config, mode="tcp")), ModbusTcpClient)


def test_run_once_writes_points_and_readiness(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = build_config(tmp_path)
    captured: dict[str, object] = {}
    monkeypatch.setattr(app, "write_line_protocol", lambda **kwargs: captured.update(kwargs))

    assert app.run_once(config) == 9
    assert config.status_file.is_file()
    assert "grid_telemetry" in str(captured["payload"])
    assert captured["token"] == "test-token"


def test_healthcheck_requires_recent_success(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = build_config(tmp_path)
    monkeypatch.setattr(AppConfig, "from_env", lambda: config)
    assert app.healthcheck() == 1

    config.status_file.write_text("100", encoding="utf-8")
    monkeypatch.setattr(app.time, "time", lambda: 110.0)
    assert app.healthcheck() == 0

    monkeypatch.setattr(app.time, "time", lambda: 200.0)
    assert app.healthcheck() == 1


@pytest.mark.parametrize(
    ("mode", "target", "result"),
    [
        ("ingest", "run_loop", 11),
        ("validate-map", "validate_map", 12),
        ("healthcheck", "healthcheck", 13),
    ],
)
def test_main_dispatches_modes(
    monkeypatch: pytest.MonkeyPatch,
    mode: str,
    target: str,
    result: int,
) -> None:
    monkeypatch.setattr(app, target, lambda: result)
    assert app.main([mode]) == result


def test_main_dispatches_ingest_once(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = build_config(tmp_path)
    calls: list[AppConfig] = []
    monkeypatch.setattr(AppConfig, "from_env", lambda: config)
    monkeypatch.setattr(app, "run_once", lambda value: calls.append(value))

    assert app.main(["ingest-once"]) == 0
    assert calls == [config]
