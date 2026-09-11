from __future__ import annotations

import io
import urllib.error
import urllib.request

import pytest
from gridguard_modbus_ingestor.influx import (
    MAX_ERROR_BODY_BYTES,
    line_protocol,
    write_line_protocol,
)


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *_args: object) -> None:
        return None


def test_line_protocol_formats_and_escapes_all_field_types() -> None:
    payload = line_protocol(
        [
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
            }
        ]
    )

    assert payload == (
        'grid\\ telemetry,site\\,name=north\\=one\\ spoof '
        'attack=true,count=2i,label="a \\"quoted\\" value",value=1.25 123'
    )


def test_write_line_protocol_rejects_non_success_status(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        urllib.request,
        "urlopen",
        lambda *_args, **_kwargs: FakeResponse(status=503),
    )

    with pytest.raises(RuntimeError, match="status 503"):
        write_line_protocol(
            influx_url="http://influx",
            org="gridguard",
            bucket="telemetry",
            token="token",
            payload="measurement value=1i 1",
            timeout_seconds=2.0,
        )


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
            payload="measurement value=1i 1",
            timeout_seconds=2.0,
        )
