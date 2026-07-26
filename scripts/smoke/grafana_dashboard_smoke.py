from __future__ import annotations

import base64
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
from typing import Any


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
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


_load_dotenv(Path(".env"))

INFLUX_URL = f"http://127.0.0.1:{_env('INFLUXDB_PORT', '8086')}"
GRAFANA_URL = f"http://127.0.0.1:{_env('GRAFANA_PORT', '3000')}"
INFLUX_ORG = _env("INFLUXDB_ORG", "gridguard")
INFLUX_BUCKET = _env("INFLUXDB_BUCKET", "gridguard_telemetry")
INFLUX_TOKEN = _env("INFLUXDB_ADMIN_TOKEN", "change-this-local-influx-token")
GRAFANA_USER = _env("GRAFANA_ADMIN_USER", "admin")
GRAFANA_PASSWORD = _env("GRAFANA_ADMIN_PASSWORD", "change-this-local-grafana-password")
DASHBOARD_PATH = Path("infra/local/grafana/dashboards/gridguard-overview.json")
DASHBOARD_UID = "gridguard-local-overview"
REQUIRED_ALERT_UIDS = {
    "gridguard-attack-flag-active",
    "gridguard-voltage-out-of-range",
    "gridguard-telemetry-stale",
}


def _basic_auth_header() -> str:
    encoded = base64.b64encode(f"{GRAFANA_USER}:{GRAFANA_PASSWORD}".encode()).decode()
    return f"Basic {encoded}"


def _request_json(
    url: str,
    *,
    data: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    method: str | None = None,
    timeout: float = 5.0,
) -> dict[str, Any]:
    payload = None if data is None else json.dumps(data).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Accept": "application/json",
            **({"Content-Type": "application/json"} if data is not None else {}),
            **(headers or {}),
        },
        method=method,
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:  # nosec B310
        return json.loads(response.read().decode("utf-8"))


def _query_influx(flux: str) -> list[dict[str, str]]:
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
    with urllib.request.urlopen(request, timeout=8.0) as response:  # nosec B310
        body = response.read().decode("utf-8")

    csv_lines = (line for line in io.StringIO(body) if not line.startswith("#"))
    return [row for row in csv.DictReader(csv_lines) if row]


def _retry(name: str, func, attempts: int = 20, delay: float = 1.0):
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


def _validate_influx() -> None:
    _retry("influxdb-health", lambda: _request_json(f"{INFLUX_URL}/health"))

    count_rows = _query_influx(
        f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -15m)
  |> filter(fn: (r) => r._measurement == "grid_telemetry")
  |> filter(fn: (r) => r._field == "value")
  |> group()
  |> count()
'''
    )
    count = sum(int(float(row.get("_value", "0") or 0)) for row in count_rows)
    if count <= 0:
        raise RuntimeError("InfluxDB has no grid_telemetry value rows in the last 15m")
    print(f"influxdb-telemetry-count: ok ({count} value rows)")

    field_rows = _query_influx(
        f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -15m)
  |> filter(fn: (r) => r._measurement == "grid_telemetry")
  |> group(columns: ["_field"])
  |> count()
  |> keep(columns: ["_field", "_value"])
'''
    )
    fields = {row.get("_field") for row in field_rows}
    required_fields = {"value", "quality", "attack_flag"}
    if not required_fields.issubset(fields):
        missing = ", ".join(sorted(required_fields - fields))
        raise RuntimeError(f"InfluxDB telemetry is missing required field(s): {missing}")
    print(f"influxdb-fields: ok ({', '.join(sorted(required_fields))})")

    source_rows = _query_influx(
        f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -15m)
  |> filter(fn: (r) => r._measurement == "grid_telemetry")
  |> filter(fn: (r) => r._field == "value")
  |> group(columns: ["source"])
  |> count()
  |> keep(columns: ["source", "_value"])
'''
    )
    sources = sorted(row.get("source", "") for row in source_rows if row.get("source"))
    if not sources:
        raise RuntimeError("InfluxDB telemetry has no source tag values in the last 15m")
    print(f"influxdb-sources: ok ({', '.join(sources)})")

    required_tags = ("feeder", "bus", "phase", "scenario", "signal", "source")
    missing_tags = [tag for tag in required_tags if not _has_tag_values(tag)]
    if missing_tags:
        raise RuntimeError(
            "InfluxDB telemetry is missing required tag value(s): "
            + ", ".join(missing_tags)
        )
    print(f"influxdb-tags: ok ({', '.join(required_tags)})")


def _has_tag_values(tag: str) -> bool:
    tag_rows = _query_influx(
        f'''
from(bucket: "{INFLUX_BUCKET}")
  |> range(start: -15m)
  |> filter(fn: (r) => r._measurement == "grid_telemetry")
  |> filter(fn: (r) => r._field == "value")
  |> filter(fn: (r) => exists r.{tag} and r.{tag} != "")
  |> group(columns: ["{tag}"])
  |> count()
  |> keep(columns: ["{tag}", "_value"])
'''
    )
    return any(row.get(tag) for row in tag_rows)


def _load_dashboard_file() -> dict[str, Any]:
    dashboard = json.loads(DASHBOARD_PATH.read_text(encoding="utf-8"))
    panels = dashboard.get("panels", [])
    if not isinstance(panels, list) or not panels:
        raise RuntimeError(f"{DASHBOARD_PATH} does not define any panels")
    return dashboard


def _validate_grafana_dashboard(dashboard: dict[str, Any]) -> None:
    _retry("grafana-health", lambda: _request_json(f"{GRAFANA_URL}/api/health"))

    _request_json(
        f"{GRAFANA_URL}/api/admin/provisioning/dashboards/reload",
        headers={"Authorization": _basic_auth_header()},
        method="POST",
    )

    provisioned = _request_json(
        f"{GRAFANA_URL}/api/dashboards/uid/{DASHBOARD_UID}",
        headers={"Authorization": _basic_auth_header()},
    )
    provisioned_dashboard = provisioned.get("dashboard", {})
    if provisioned_dashboard.get("uid") != DASHBOARD_UID:
        raise RuntimeError(f"Grafana did not return dashboard uid {DASHBOARD_UID}")
    if len(provisioned_dashboard.get("panels", [])) != len(dashboard["panels"]):
        raise RuntimeError("Grafana provisioned panel count does not match local dashboard")

    print(f"grafana-dashboard: ok ({provisioned_dashboard.get('title', DASHBOARD_UID)})")

    for panel in provisioned_dashboard["panels"]:
        title = str(panel.get("title", f"panel-{panel.get('id', 'unknown')}"))
        targets = panel.get("targets", [])
        if not targets:
            raise RuntimeError(f"{title} has no query targets")

        for target in targets:
            ref_id = str(target.get("refId", "A"))
            resolved_target = {
                **target,
                "query": _resolve_dashboard_variables(str(target.get("query", ""))),
            }
            payload = {
                "from": "now-15m",
                "to": "now",
                "queries": [
                    {
                        **resolved_target,
                        "datasource": {
                            "type": "influxdb",
                            "uid": "gridguard-influxdb",
                        },
                        "intervalMs": 5000,
                        "maxDataPoints": 600,
                        "queryType": "flux",
                    }
                ],
            }
            response = _request_json(
                f"{GRAFANA_URL}/api/ds/query",
                data=payload,
                headers={"Authorization": _basic_auth_header()},
                method="POST",
                timeout=10.0,
            )
            result = response.get("results", {}).get(ref_id, {})
            if result.get("error"):
                raise RuntimeError(f"{title} query failed: {result['error']}")

            frames = result.get("frames", [])
            if not frames:
                raise RuntimeError(f"{title} query returned no data frames")

            print(f"grafana-panel: ok ({title})")


def _validate_grafana_alerts() -> None:
    _request_json(
        f"{GRAFANA_URL}/api/admin/provisioning/alerting/reload",
        headers={"Authorization": _basic_auth_header()},
        method="POST",
    )

    rules = _request_json(
        f"{GRAFANA_URL}/api/v1/provisioning/alert-rules",
        headers={"Authorization": _basic_auth_header()},
    )
    rule_list = rules.get("rules", []) if isinstance(rules, dict) else rules

    provisioned_uids = {
        str(rule.get("uid", "")) for rule in rule_list if isinstance(rule, dict)
    }
    missing = REQUIRED_ALERT_UIDS - provisioned_uids
    if missing:
        raise RuntimeError(
            "Grafana is missing provisioned alert rule(s): "
            + ", ".join(sorted(missing))
        )

    print(f"grafana-alerts: ok ({len(REQUIRED_ALERT_UIDS)} rules)")


def _resolve_dashboard_variables(query: str) -> str:
    replacements = {
        "${feeder:regex}": ".*",
        "${source:regex}": ".*",
        "${scenario:regex}": ".*",
    }
    for placeholder, value in replacements.items():
        query = query.replace(placeholder, value)
    return query


def main() -> int:
    try:
        dashboard = _load_dashboard_file()
        _validate_influx()
        _validate_grafana_dashboard(dashboard)
        _validate_grafana_alerts()
    except Exception as exc:
        print(f"dashboard smoke-test failed: {exc}", file=sys.stderr)
        return 1

    print("Grafana dashboard smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
