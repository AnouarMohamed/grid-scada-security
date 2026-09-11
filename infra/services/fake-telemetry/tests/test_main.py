from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import gridguard_fake_telemetry.main as app
import pytest
from gridguard_fake_telemetry.config import IngestConfig, SourceConfig


class FakeResponse:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *_args: object) -> None:
        return None


def test_request_path_ignores_query_string() -> None:
    assert app.request_path("/measurements?format=json") == "/measurements"


def test_ingestor_healthcheck_requires_recent_success(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    status_file = tmp_path / "ready"
    config = SimpleNamespace(status_file=status_file, interval_seconds=2.0)
    monkeypatch.setattr(IngestConfig, "from_env", lambda: config)

    assert app.healthcheck_ingestor() == 1
    status_file.write_text("100", encoding="utf-8")
    monkeypatch.setattr(app.time, "time", lambda: 110.0)
    assert app.healthcheck_ingestor() == 0
    monkeypatch.setattr(app.time, "time", lambda: 200.0)
    assert app.healthcheck_ingestor() == 1


def test_source_healthcheck_handles_status_and_network_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = SimpleNamespace(port=8080)
    monkeypatch.setattr(SourceConfig, "from_env", lambda: config)
    monkeypatch.setattr(app.urllib.request, "urlopen", lambda *_args, **_kwargs: FakeResponse())
    assert app.healthcheck_source() == 0

    def raise_network_error(*_args: object, **_kwargs: object) -> None:
        raise OSError("unreachable")

    monkeypatch.setattr(app.urllib.request, "urlopen", raise_network_error)
    assert app.healthcheck_source() == 1


@pytest.mark.parametrize(
    ("mode", "target", "result"),
    [
        ("source", "run_source", 11),
        ("ingest", "run_ingestor", 12),
        ("healthcheck-source", "healthcheck_source", 13),
        ("healthcheck-ingestor", "healthcheck_ingestor", 14),
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
