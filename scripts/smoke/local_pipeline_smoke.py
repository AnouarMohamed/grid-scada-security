from __future__ import annotations

import csv
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def _env(name: str, default: str) -> str:
    return os.getenv(name, default)


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            os.environ.setdefault(key, value)


_load_dotenv(Path(".env"))

INFLUX_URL = f"http://127.0.0.1:{_env('INFLUXDB_PORT', '8086')}"
GRAFANA_URL = f"http://127.0.0.1:{_env('GRAFANA_PORT', '3000')}"
INFLUX_ORG = _env("INFLUXDB_ORG", "gridguard")
INFLUX_BUCKET = _env("INFLUXDB_BUCKET", "gridguard_telemetry")
INFLUX_TOKEN = _env("INFLUXDB_ADMIN_TOKEN", "change-this-local-influx-token")
SMOKE_SOURCE = os.getenv("GRIDGUARD_SMOKE_SOURCE")


def _get_json(url: str, timeout: float = 3.0) -> dict[str, object]:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # nosec B310
        return json.loads(response.read().decode("utf-8"))


def _flux_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _query_influx() -> list[dict[str, str]]:
    source_filter = ""
    if SMOKE_SOURCE:
        source_filter = f'  |> filter(fn: (r) => r.source == "{_flux_string(SMOKE_SOURCE)}")\n'

    flux = f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "grid_telemetry")
{source_filter}  |> filter(fn: (r) => r._field == "value")
  |> limit(n: 5)
'''
    query = urllib.parse.urlencode({"org": INFLUX_ORG})
    request = urllib.request.Request(
        f"{INFLUX_URL}/api/v2/query?{query}",
        data=json.dumps({"query": flux, "type": "flux"}).encode("utf-8"),
        headers={
            "Authorization": f"Token {INFLUX_TOKEN}",
            "Accept": "application/csv",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=5.0) as response:  # nosec B310
        body = response.read().decode("utf-8")

    rows: list[dict[str, str]] = []
    for row in csv.DictReader(line for line in io.StringIO(body) if not line.startswith("#")):
        if row.get("_measurement") == "grid_telemetry":
            rows.append(row)
    return rows


def _retry(name: str, func, attempts: int = 30, delay: float = 2.0):
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            result = func()
            if result:
                print(f"{name}: ok")
                return result
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            last_error = exc
        time.sleep(delay)

    if last_error is not None:
        raise RuntimeError(f"{name} did not become ready: {last_error}") from last_error
    raise RuntimeError(f"{name} did not become ready")


def main() -> int:
    try:
        _retry("influxdb-health", lambda: _get_json(f"{INFLUX_URL}/health"))
        _retry("grafana-health", lambda: _get_json(f"{GRAFANA_URL}/api/health"))
        rows = _retry("telemetry-query", _query_influx, attempts=45, delay=2.0)
    except Exception as exc:
        print(f"smoke-test failed: {exc}", file=sys.stderr)
        return 1

    print(f"telemetry rows observed: {len(rows)}")
    print("local pipeline smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
