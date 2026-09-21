#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

readonly OT_NAMESPACE="gridguard-ot"
readonly INGESTION_NAMESPACE="gridguard-ingestion"
readonly OBSERVABILITY_NAMESPACE="gridguard-observability"
readonly AWS_OVERLAY="infra/kubernetes/overlays/aws"

usage() {
  cat <<'EOF'
Usage: scripts/dev/eks-lab.sh <command>

Commands:
  deploy       Create ephemeral secrets/config maps and deploy the AWS overlay.
  baseline     Select the baseline Modbus scenario.
  naive        Select the obvious false-data-injection scenario.
  stealthy     Select the coordinated in-envelope attack scenario.
  status       Show nodes, workloads, services, and network policies.
  forward      Forward Grafana to 127.0.0.1:3000 and InfluxDB to 127.0.0.1:8086.
  remove-app   Remove application namespaces and every in-cluster secret.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command is not installed: $1" >&2
    exit 1
  }
}

require_cluster() {
  require_command kubectl
  local context
  context="$(kubectl config current-context)"
  if [[ "${context}" != *"gridguard-aws-eks-lab"* ]]; then
    echo "Refusing context '${context}'; expected gridguard-aws-eks-lab." >&2
    exit 1
  fi
  kubectl cluster-info >/dev/null
}

load_local_environment() {
  if [[ ! -f .env ]]; then
    echo "Missing ignored .env; copy .env.example and set strong local-only values." >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  local required=(
    INFLUXDB_ADMIN_USER
    INFLUXDB_ADMIN_PASSWORD
    INFLUXDB_ADMIN_TOKEN
    INFLUXDB_ORG
    INFLUXDB_BUCKET
    INFLUXDB_RETENTION
    GRAFANA_ADMIN_USER
    GRAFANA_ADMIN_PASSWORD
  )
  local name
  for name in "${required[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      echo ".env is missing required value ${name}." >&2
      exit 1
    fi
  done
}

apply_secret_from_file() {
  local namespace="$1"
  local name="$2"
  local env_file="$3"
  kubectl create secret generic "${name}" \
    --namespace "${namespace}" \
    --from-env-file="${env_file}" \
    --dry-run=client \
    --output=yaml | kubectl apply -f - >/dev/null
}

configure_runtime_data() {
  load_local_environment
  kubectl apply -f infra/kubernetes/base/namespaces.yaml >/dev/null

  local secret_dir
  secret_dir="$(mktemp -d)"
  chmod 700 "${secret_dir}"
  trap "rm -rf -- '${secret_dir}'" EXIT

  {
    printf 'DOCKER_INFLUXDB_INIT_MODE=setup\n'
    printf 'DOCKER_INFLUXDB_INIT_USERNAME=%s\n' "${INFLUXDB_ADMIN_USER}"
    printf 'DOCKER_INFLUXDB_INIT_PASSWORD=%s\n' "${INFLUXDB_ADMIN_PASSWORD}"
    printf 'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=%s\n' "${INFLUXDB_ADMIN_TOKEN}"
    printf 'DOCKER_INFLUXDB_INIT_ORG=%s\n' "${INFLUXDB_ORG}"
    printf 'DOCKER_INFLUXDB_INIT_BUCKET=%s\n' "${INFLUXDB_BUCKET}"
    printf 'DOCKER_INFLUXDB_INIT_RETENTION=%s\n' "${INFLUXDB_RETENTION}"
  } >"${secret_dir}/influx.env"

  printf 'GRIDGUARD_INFLUX_TOKEN=%s\n' \
    "${INFLUXDB_ADMIN_TOKEN}" >"${secret_dir}/ingestor.env"

  {
    printf 'GF_SECURITY_ADMIN_USER=%s\n' "${GRAFANA_ADMIN_USER}"
    printf 'GF_SECURITY_ADMIN_PASSWORD=%s\n' "${GRAFANA_ADMIN_PASSWORD}"
    printf 'INFLUXDB_ORG=%s\n' "${INFLUXDB_ORG}"
    printf 'INFLUXDB_BUCKET=%s\n' "${INFLUXDB_BUCKET}"
    printf 'INFLUXDB_ADMIN_TOKEN=%s\n' "${INFLUXDB_ADMIN_TOKEN}"
  } >"${secret_dir}/grafana.env"
  chmod 600 "${secret_dir}"/*.env

  apply_secret_from_file "${OBSERVABILITY_NAMESPACE}" influxdb-runtime \
    "${secret_dir}/influx.env"
  apply_secret_from_file "${INGESTION_NAMESPACE}" modbus-ingestor-runtime \
    "${secret_dir}/ingestor.env"
  apply_secret_from_file "${OBSERVABILITY_NAMESPACE}" grafana-runtime \
    "${secret_dir}/grafana.env"

  kubectl create configmap grafana-datasource \
    --namespace "${OBSERVABILITY_NAMESPACE}" \
    --from-file=gridguard.yml=infra/local/grafana/provisioning/datasources/influxdb.yml \
    --dry-run=client --output=yaml | kubectl apply -f - >/dev/null
  kubectl create configmap grafana-dashboard-provider \
    --namespace "${OBSERVABILITY_NAMESPACE}" \
    --from-file=gridguard.yml=infra/local/grafana/provisioning/dashboards/gridguard.yml \
    --dry-run=client --output=yaml | kubectl apply -f - >/dev/null
  kubectl create configmap grafana-alerting \
    --namespace "${OBSERVABILITY_NAMESPACE}" \
    --from-file=gridguard.yml=infra/local/grafana/provisioning/alerting/gridguard.yml \
    --dry-run=client --output=yaml | kubectl apply -f - >/dev/null
  kubectl create configmap grafana-dashboard \
    --namespace "${OBSERVABILITY_NAMESPACE}" \
    --from-file=gridguard-overview.json=infra/local/grafana/dashboards/gridguard-overview.json \
    --dry-run=client --output=yaml | kubectl apply -f - >/dev/null
  rm -rf "${secret_dir}"
  trap - EXIT
}

deploy() {
  require_cluster
  configure_runtime_data
  kubectl apply -k "${AWS_OVERLAY}"
  kubectl rollout status deployment/influxdb \
    --namespace "${OBSERVABILITY_NAMESPACE}" --timeout=10m
  kubectl rollout status deployment/power-sim \
    --namespace "${OT_NAMESPACE}" --timeout=10m
  kubectl rollout status deployment/grafana \
    --namespace "${OBSERVABILITY_NAMESPACE}" --timeout=10m
  kubectl rollout status deployment/modbus-ingestor \
    --namespace "${INGESTION_NAMESPACE}" --timeout=10m
}

set_scenario() {
  local scenario="$1"
  local attack_flag="$2"
  require_cluster
  kubectl set env deployment/power-sim \
    --namespace "${OT_NAMESPACE}" GRIDGUARD_SCENARIO="${scenario}"
  kubectl set env deployment/modbus-ingestor \
    --namespace "${INGESTION_NAMESPACE}" \
    GRIDGUARD_SCENARIO="${scenario}" GRIDGUARD_ATTACK_FLAG="${attack_flag}"
  kubectl rollout status deployment/power-sim \
    --namespace "${OT_NAMESPACE}" --timeout=5m
  kubectl rollout status deployment/modbus-ingestor \
    --namespace "${INGESTION_NAMESPACE}" --timeout=5m
}

status() {
  require_cluster
  kubectl get nodes -o wide
  kubectl get deployments,pods,services \
    --all-namespaces --selector app.kubernetes.io/part-of=gridguard -o wide
  kubectl get networkpolicies --all-namespaces
}

forward() {
  require_cluster
  echo "Grafana:  http://127.0.0.1:3000"
  echo "InfluxDB: http://127.0.0.1:8086"
  kubectl port-forward --address 127.0.0.1 \
    --namespace "${OBSERVABILITY_NAMESPACE}" service/grafana 3000:3000 &
  local grafana_pid=$!
  kubectl port-forward --address 127.0.0.1 \
    --namespace "${OBSERVABILITY_NAMESPACE}" service/influxdb 8086:8086 &
  local influx_pid=$!
  trap 'kill "${grafana_pid}" "${influx_pid}" 2>/dev/null || true' EXIT
  wait
}

remove_app() {
  require_cluster
  kubectl delete namespace \
    "${OT_NAMESPACE}" "${INGESTION_NAMESPACE}" "${OBSERVABILITY_NAMESPACE}" \
    --ignore-not-found --wait=true
}

command="${1:-}"
case "${command}" in
  deploy) deploy ;;
  baseline) set_scenario baseline-modbus 0 ;;
  naive) set_scenario naive-bad-value 1 ;;
  stealthy) set_scenario stealthy-fdia 1 ;;
  status) status ;;
  forward) forward ;;
  remove-app) remove_app ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 2 ;;
esac
