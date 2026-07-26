#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

usage() {
  cat <<'EOF'
Usage: scripts/dev/local-stack.sh <command>

Commands:
  up       Build and start the fake telemetry, InfluxDB, and Grafana stack.
  modbus-up
           Build and start the Modbus fixture ingestor, InfluxDB, and Grafana stack.
  down     Stop containers and keep named volumes.
  reset    Stop containers and remove named volumes.
  logs     Follow stack logs.
  ps       Show stack container status.
  smoke    Run the local pipeline smoke test.
  modbus-smoke
           Run the local smoke test against Modbus fixture rows.
  dashboard-smoke
           Validate InfluxDB health and every provisioned Grafana dashboard panel.
EOF
}

command="${1:-}"

case "${command}" in
  up)
    docker compose --profile fake up -d --build
    ;;
  modbus-up)
    docker compose --profile modbus-fixture up -d --build \
      influxdb grafana modbus-ingestor-fixture
    ;;
  down)
    docker compose --profile fake --profile modbus-fixture down
    ;;
  reset)
    docker compose --profile fake --profile modbus-fixture down --volumes --remove-orphans
    ;;
  logs)
    docker compose --profile fake --profile modbus-fixture logs -f --tail=120
    ;;
  ps)
    docker compose --profile fake --profile modbus-fixture ps
    ;;
  smoke)
    python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  modbus-smoke)
    GRIDGUARD_SMOKE_SOURCE=modbus_fixture python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  dashboard-smoke)
    python3 scripts/smoke/grafana_dashboard_smoke.py
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
