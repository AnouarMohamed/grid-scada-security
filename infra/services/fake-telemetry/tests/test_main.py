from __future__ import annotations

from gridguard_fake_telemetry.main import request_path


def test_request_path_ignores_query_string() -> None:
    assert request_path("/measurements?format=json") == "/measurements"
