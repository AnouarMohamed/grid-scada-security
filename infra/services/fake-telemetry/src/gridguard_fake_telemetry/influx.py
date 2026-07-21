from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


def _escape_key(value: str) -> str:
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
        payload = response.read().decode("utf-8")
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
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"InfluxDB write failed with status {exc.code}: {body}") from exc
