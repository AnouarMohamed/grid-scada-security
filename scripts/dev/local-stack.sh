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
  live-up  Build and start the real power simulator and live Modbus pipeline.
  naive-up Start the live pipeline with an obvious false-data injection.
  stealthy-up
           Start the live pipeline with a coordinated in-envelope FDIA.
  down     Stop containers and keep named volumes.
  reset    Stop containers and remove named volumes.
  logs     Follow stack logs.
  ps       Show stack container status.
  smoke    Run the local pipeline smoke test.
  modbus-smoke
           Run the local smoke test against Modbus fixture rows.
  live-smoke
           Run the local smoke test against live Modbus rows.
  attack-smoke
           Require detector output from the active attack scenario.
  naive-smoke
           Require attack-flag and voltage-envelope detections.
  stealthy-smoke
           Require attack-flag detection and no voltage-envelope detection.
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
  live-up)
    GRIDGUARD_SCENARIO=baseline-modbus GRIDGUARD_ATTACK_FLAG=0 \
      docker compose --profile live up -d --build \
      influxdb grafana power-sim modbus-ingestor-live
    ;;
  naive-up)
    GRIDGUARD_SCENARIO=naive-bad-value GRIDGUARD_ATTACK_FLAG=1 \
      docker compose --profile live up -d --build --force-recreate \
      influxdb grafana power-sim modbus-ingestor-live
    ;;
  stealthy-up)
    GRIDGUARD_SCENARIO=stealthy-fdia GRIDGUARD_ATTACK_FLAG=1 \
      docker compose --profile live up -d --build --force-recreate \
      influxdb grafana power-sim modbus-ingestor-live
    ;;
  down)
    docker compose --profile fake --profile modbus-fixture --profile live down
    ;;
  reset)
    docker compose --profile fake --profile modbus-fixture --profile live down --volumes --remove-orphans
    ;;
  logs)
    docker compose --profile fake --profile modbus-fixture --profile live logs -f --tail=120
    ;;
  ps)
    docker compose --profile fake --profile modbus-fixture --profile live ps
    ;;
  smoke)
    python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  modbus-smoke)
    GRIDGUARD_SMOKE_SOURCE=modbus_fixture python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  live-smoke)
    GRIDGUARD_SMOKE_SOURCE=modbus_tcp python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  attack-smoke)
    python3 scripts/smoke/detection_smoke.py
    ;;
  naive-smoke)
    GRIDGUARD_SMOKE_SCENARIO=naive-bad-value \
      GRIDGUARD_EXPECT_DETECTORS=attack-flag-forwarder,voltage-envelope \
      python3 scripts/smoke/detection_smoke.py
    ;;
  stealthy-smoke)
    GRIDGUARD_SMOKE_SCENARIO=stealthy-fdia \
      GRIDGUARD_EXPECT_DETECTORS=attack-flag-forwarder \
      python3 scripts/smoke/detection_smoke.py
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
