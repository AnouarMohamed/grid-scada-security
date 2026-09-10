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


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


_load_dotenv(Path(".env"))

INFLUX_URL = f"http://127.0.0.1:{os.getenv('INFLUXDB_PORT', '8086')}"
INFLUX_ORG = os.getenv("INFLUXDB_ORG", "gridguard")
INFLUX_BUCKET = os.getenv("INFLUXDB_BUCKET", "gridguard_telemetry")
INFLUX_TOKEN = os.getenv("INFLUXDB_ADMIN_TOKEN", "change-this-local-influx-token")
SMOKE_SCENARIO = os.getenv("GRIDGUARD_SMOKE_SCENARIO")
EXPECTED_DETECTORS = {
    item.strip()
    for item in os.getenv("GRIDGUARD_EXPECT_DETECTORS", "").split(",")
    if item.strip()
}


def _query() -> list[dict[str, str]]:
    scenario_filter = ""
    if SMOKE_SCENARIO:
        escaped = SMOKE_SCENARIO.replace("\\", "\\\\").replace('"', '\\"')
        scenario_filter = f'  |> filter(fn: (r) => r.scenario == "{escaped}")\n'
    flux = f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "grid_detection")
{scenario_filter}  |> filter(fn: (r) => r._field == "alert_flag" and r._value == 1)
  |> limit(n: 20)
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
    csv_lines = (line for line in io.StringIO(body) if not line.startswith("#"))
    return [
        row
        for row in csv.DictReader(csv_lines)
        if row.get("_measurement") == "grid_detection"
    ]


def main() -> int:
    last_error: Exception | None = None
    for _ in range(45):
        try:
            rows = _query()
            if rows:
                detectors = {row.get("detector", "") for row in rows}
                if EXPECTED_DETECTORS and detectors != EXPECTED_DETECTORS:
                    expected = sorted(EXPECTED_DETECTORS)
                    observed = sorted(detectors)
                    raise RuntimeError(
                        f"expected detectors {expected}, got {observed}"
                    )
                print(f"detection rows observed: {len(rows)}")
                print(f"detectors: {', '.join(sorted(detectors))}")
                print("attack detection smoke test passed")
                return 0
        except (
            urllib.error.URLError,
            TimeoutError,
            OSError,
            json.JSONDecodeError,
            RuntimeError,
        ) as exc:
            last_error = exc
        time.sleep(2.0)
    print(f"attack detection smoke test failed: {last_error or 'no rows'}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
