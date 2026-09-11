from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

MAX_SNAPSHOT_BYTES = 1024 * 1024
MAX_ERROR_BODY_BYTES = 4096


def _line_safe(value: str) -> str:
    return value.replace("\r", " ").replace("\n", " ").replace("\t", " ")


def _escape_key(value: str) -> str:
    value = _line_safe(value)
    return (
        value.replace("\\", "\\\\")
        .replace(" ", "\\ ")
        .replace(",", "\\,")
        .replace("=", "\\=")
    )


def _format_field_value(value: float | int | bool | str) -> str:
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, int):
        return f"{value}i"
    if isinstance(value, float):
        return repr(value)
    value = _line_safe(value)
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def snapshot_to_line_protocol(snapshot: dict[str, Any]) -> str:
    lines: list[str] = []

    for point in snapshot.get("points", []):
        measurement = _escape_key(str(point["measurement"]))
        tags = {
            str(key): str(value)
            for key, value in sorted(point.get("tags", {}).items())
            if value is not None
        }
        fields = point.get("fields", {})
        timestamp_ns = int(point["timestamp_ns"])

        tag_segment = "".join(
            f",{_escape_key(key)}={_escape_key(value)}" for key, value in tags.items()
        )
        field_segment = ",".join(
            f"{_escape_key(str(key))}={_format_field_value(value)}"
            for key, value in sorted(fields.items())
        )

        if not field_segment:
            continue

        lines.append(f"{measurement}{tag_segment} {field_segment} {timestamp_ns}")

    return "\n".join(lines)


def fetch_snapshot(source_url: str, timeout_seconds: float) -> dict[str, Any]:
    request = urllib.request.Request(source_url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:  # nosec B310
        raw_payload = response.read(MAX_SNAPSHOT_BYTES + 1)
    if len(raw_payload) > MAX_SNAPSHOT_BYTES:
        raise RuntimeError("telemetry snapshot exceeds 1 MiB limit")
    payload = raw_payload.decode("utf-8")
    return json.loads(payload)


def write_line_protocol(
    *,
    influx_url: str,
    org: str,
    bucket: str,
    token: str,
    line_protocol: str,
    timeout_seconds: float,
) -> None:
    query = urllib.parse.urlencode(
        {
            "org": org,
            "bucket": bucket,
            "precision": "ns",
        }
    )
    endpoint = f"{influx_url.rstrip('/')}/api/v2/write?{query}"
    request = urllib.request.Request(
        endpoint,
        data=line_protocol.encode("utf-8"),
        headers={
            "Authorization": f"Token {token}",
            "Content-Type": "text/plain; charset=utf-8",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:  # nosec B310
            if response.status >= 300:
                raise RuntimeError(f"InfluxDB write failed with status {response.status}")
    except urllib.error.HTTPError as exc:
        raw_body = exc.read(MAX_ERROR_BODY_BYTES + 1)
        suffix = " [truncated]" if len(raw_body) > MAX_ERROR_BODY_BYTES else ""
        body = raw_body[:MAX_ERROR_BODY_BYTES].decode("utf-8", errors="replace") + suffix
        raise RuntimeError(f"InfluxDB write failed with status {exc.code}: {body}") from exc
