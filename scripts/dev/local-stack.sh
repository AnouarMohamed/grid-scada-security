#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

usage() {
  cat <<'EOF'
Usage: scripts/dev/local-stack.sh <command>

Commands:
  up       Build and start the fake telemetry, InfluxDB, and Grafana stack.
  down     Stop containers and keep named volumes.
  reset    Stop containers and remove named volumes.
  logs     Follow stack logs.
  ps       Show stack container status.
  smoke    Run the local pipeline smoke test.
EOF
}

command="${1:-}"

case "${command}" in
  up)
    docker compose up -d --build
    ;;
  down)
    docker compose down
    ;;
  reset)
    docker compose down --volumes --remove-orphans
    ;;
  logs)
    docker compose logs -f --tail=120
    ;;
  ps)
    docker compose ps
    ;;
  smoke)
    python3 scripts/smoke/local_pipeline_smoke.py
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
