from __future__ import annotations

import urllib.error
import urllib.parse
import urllib.request


def line_protocol(points: list[dict[str, object]]) -> str:
    lines: list[str] = []
    for point in points:
        measurement = _escape_key(str(point["measurement"]))
        tags = {
            str(key): str(value)
            for key, value in sorted(dict(point["tags"]).items())
            if value is not None
        }
        fields = dict(point["fields"])
        timestamp_ns = int(point["timestamp_ns"])

        tag_segment = "".join(
            f",{_escape_key(key)}={_escape_key(value)}" for key, value in tags.items()
        )
        field_segment = ",".join(
            f"{_escape_key(str(key))}={_format_field(value)}"
            for key, value in sorted(fields.items())
        )
        lines.append(f"{measurement}{tag_segment} {field_segment} {timestamp_ns}")

    return "\n".join(lines)


def write_line_protocol(
    *,
    influx_url: str,
    org: str,
    bucket: str,
    token: str,
    payload: str,
    timeout_seconds: float,
) -> None:
    query = urllib.parse.urlencode({"org": org, "bucket": bucket, "precision": "ns"})
    request = urllib.request.Request(
        f"{influx_url.rstrip('/')}/api/v2/write?{query}",
        data=payload.encode("utf-8"),
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


def _format_field(value: object) -> str:
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, int):
        return f"{value}i"
    if isinstance(value, float):
        return repr(value)
    escaped = _line_safe(str(value)).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'

