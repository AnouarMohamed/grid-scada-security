from __future__ import annotations

import io
import urllib.error
import urllib.request

import pytest
from gridguard_fake_telemetry.influx import (
    MAX_ERROR_BODY_BYTES,
    MAX_SNAPSHOT_BYTES,
    fetch_snapshot,
    snapshot_to_line_protocol,
    write_line_protocol,
)


class FakeResponse:
    def __init__(self, body: bytes = b"", status: int = 200) -> None:
        self.body = body
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self, size: int = -1) -> bytes:
        return self.body if size < 0 else self.body[:size]


def test_snapshot_to_line_protocol_escapes_untrusted_values() -> None:
    payload = snapshot_to_line_protocol(
        {
            "points": [
                {
                    "measurement": "grid telemetry",
                    "tags": {"site,name": "north=one\nspoof"},
                    "fields": {
                        "attack": True,
                        "count": 2,
                        "label": 'a "quoted" value',
                        "value": 1.25,
                    },
                    "timestamp_ns": 123,
                },
                {
                    "measurement": "empty",
                    "fields": {},
                    "timestamp_ns": 124,
                },
            ]
        }
    )

    assert payload == (
        'grid\\ telemetry,site\\,name=north\\=one\\ spoof '
        'attack=true,count=2i,label="a \\"quoted\\" value",value=1.25 123'
    )


def test_fetch_snapshot_bounds_response_size(monkeypatch: pytest.MonkeyPatch) -> None:
    body = b'{"snapshot_id":"ok"}'

    def fake_urlopen(request: urllib.request.Request, timeout: float) -> FakeResponse:
        assert request.get_header("Accept") == "application/json"
        assert timeout == 1.5
        return FakeResponse(body)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    assert fetch_snapshot("http://source/measurements", 1.5) == {"snapshot_id": "ok"}

    monkeypatch.setattr(
        urllib.request,
        "urlopen",
        lambda *_args, **_kwargs: FakeResponse(b"x" * (MAX_SNAPSHOT_BYTES + 1)),
    )
    with pytest.raises(RuntimeError, match="exceeds 1 MiB"):
        fetch_snapshot("http://source/measurements", 1.5)


def test_write_line_protocol_builds_authenticated_request(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}

    def fake_urlopen(request: urllib.request.Request, timeout: float) -> FakeResponse:
        captured.update(request=request, timeout=timeout)
        return FakeResponse(status=204)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    write_line_protocol(
        influx_url="http://influx/",
        org="grid guard",
        bucket="telemetry",
        token="secret-token",
        line_protocol="measurement value=1i 1",
        timeout_seconds=2.0,
    )

    request = captured["request"]
    assert isinstance(request, urllib.request.Request)
    assert request.full_url == (
        "http://influx/api/v2/write?org=grid+guard&bucket=telemetry&precision=ns"
    )
    assert request.method == "POST"
    assert request.data == b"measurement value=1i 1"
    assert request.get_header("Authorization") == "Token secret-token"
    assert captured["timeout"] == 2.0


def test_write_line_protocol_truncates_http_error_body(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    error = urllib.error.HTTPError(
        "http://influx",
        400,
        "bad request",
        {},
        io.BytesIO(b"x" * (MAX_ERROR_BODY_BYTES + 10)),
    )
    def raise_http_error(*_args: object, **_kwargs: object) -> FakeResponse:
        raise error

    monkeypatch.setattr(urllib.request, "urlopen", raise_http_error)

    with pytest.raises(RuntimeError, match=r"status 400: x+ \[truncated\]$"):
        write_line_protocol(
            influx_url="http://influx",
            org="gridguard",
            bucket="telemetry",
            token="token",
            line_protocol="measurement value=1i 1",
            timeout_seconds=2.0,
        )
