from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _get_int(name: str, default: int) -> int:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return int(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {raw_value!r}") from exc


def _get_float(name: str, default: float) -> float:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    try:
        return float(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number, got {raw_value!r}") from exc


@dataclass(frozen=True)
class SourceConfig:
    host: str
    port: int
    feeder_id: str
    scenario: str

    @classmethod
    def from_env(cls) -> SourceConfig:
        return cls(
            host=os.getenv("GRIDGUARD_SOURCE_HOST", "127.0.0.1"),
            port=_get_int("GRIDGUARD_SOURCE_PORT", 8080),
            feeder_id=os.getenv("GRIDGUARD_FEEDER_ID", "ieee-13-demo"),
            scenario=os.getenv("GRIDGUARD_SCENARIO", "baseline-fake"),
        )


@dataclass(frozen=True)
class IngestConfig:
    source_url: str
    influx_url: str
    org: str
    bucket: str
    token: str
    interval_seconds: float
    request_timeout_seconds: float
    status_file: Path

    @classmethod
    def from_env(cls) -> IngestConfig:
        return cls(
            source_url=os.getenv(
                "GRIDGUARD_SOURCE_URL",
                "http://127.0.0.1:8080/measurements",
            ),
            influx_url=os.getenv("GRIDGUARD_INFLUX_URL", "http://127.0.0.1:8086"),
            org=os.getenv("GRIDGUARD_INFLUX_ORG", "gridguard"),
            bucket=os.getenv("GRIDGUARD_INFLUX_BUCKET", "gridguard_telemetry"),
            token=os.getenv("GRIDGUARD_INFLUX_TOKEN", "change-this-local-influx-token"),
            interval_seconds=_get_float("GRIDGUARD_INGEST_INTERVAL_SECONDS", 2.0),
            request_timeout_seconds=_get_float("GRIDGUARD_REQUEST_TIMEOUT_SECONDS", 5.0),
            status_file=Path(
                os.getenv(
                    "GRIDGUARD_INGEST_STATUS_FILE",
                    "/tmp/gridguard-ingestor-ready",
                )
            ),
        )
