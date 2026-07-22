from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env(name: str, default: str) -> str:
    return os.getenv(name, default)


def _int(name: str, default: int) -> int:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return int(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {raw_value!r}") from exc


def _optional_int(name: str) -> int | None:
    raw_value = os.getenv(name)
    if raw_value is None or raw_value == "":
        return None
    try:
        return int(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {raw_value!r}") from exc


def _port(name: str, default: int) -> int:
    value = _int(name, default)
    if value < 1 or value > 65535:
        raise ValueError(f"{name} must be between 1 and 65535, got {value!r}")
    return value


def _positive_float(name: str, default: float) -> float:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        value = float(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number, got {raw_value!r}") from exc
    if value <= 0:
        raise ValueError(f"{name} must be greater than zero, got {value!r}")
    return value


@dataclass(frozen=True)
class AppConfig:
    mode: str
    register_map: Path
    register_fixture: Path
    source_id: str
    modbus_host: str
    modbus_port: int
    modbus_unit_id: int | None
    interval_seconds: float
    request_timeout_seconds: float
    status_file: Path
    influx_url: str
    influx_org: str
    influx_bucket: str
    influx_token: str

    @classmethod
    def from_env(cls) -> AppConfig:
        mode = _env("GRIDGUARD_MODBUS_MODE", "fixture")
        if mode not in {"fixture", "tcp"}:
            raise ValueError("GRIDGUARD_MODBUS_MODE must be fixture or tcp")

        unit_id = _optional_int("GRIDGUARD_MODBUS_UNIT_ID")
        if unit_id is not None and (unit_id < 1 or unit_id > 247):
            raise ValueError("GRIDGUARD_MODBUS_UNIT_ID must be between 1 and 247")

        return cls(
            mode=mode,
            register_map=Path(
                _env("GRIDGUARD_REGISTER_MAP", "/etc/gridguard/register-map.json")
            ),
            register_fixture=Path(
                _env("GRIDGUARD_REGISTER_FIXTURE", "/etc/gridguard/register-values.json")
            ),
            source_id=_env("GRIDGUARD_MODBUS_SOURCE_ID", f"modbus_{mode}"),
            modbus_host=_env("GRIDGUARD_MODBUS_HOST", "modbus-simulator"),
            modbus_port=_port("GRIDGUARD_MODBUS_PORT", 502),
            modbus_unit_id=unit_id,
            interval_seconds=_positive_float("GRIDGUARD_MODBUS_INGEST_INTERVAL_SECONDS", 2.0),
            request_timeout_seconds=_positive_float("GRIDGUARD_MODBUS_TIMEOUT_SECONDS", 5.0),
            status_file=Path(
                _env(
                    "GRIDGUARD_MODBUS_STATUS_FILE",
                    "/tmp/gridguard-modbus-ingestor-ready",  # nosec B108
                )
            ),
            influx_url=_env("GRIDGUARD_INFLUX_URL", "http://127.0.0.1:8086"),
            influx_org=_env("GRIDGUARD_INFLUX_ORG", "gridguard"),
            influx_bucket=_env("GRIDGUARD_INFLUX_BUCKET", "gridguard_telemetry"),
            influx_token=_env("GRIDGUARD_INFLUX_TOKEN", "change-this-local-influx-token"),
        )
