#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

readonly OT_NAMESPACE="gridguard-ot"
readonly INGESTION_NAMESPACE="gridguard-ingestion"
readonly OBSERVABILITY_NAMESPACE="gridguard-observability"

context="$(kubectl config current-context)"
if [[ "${context}" != *"gridguard-aws-eks-lab"* ]]; then
  echo "Refusing context '${context}'; expected gridguard-aws-eks-lab." >&2
  exit 1
fi

for deployment in \
  "${OT_NAMESPACE}/power-sim" \
  "${INGESTION_NAMESPACE}/modbus-ingestor" \
  "${OBSERVABILITY_NAMESPACE}/influxdb" \
  "${OBSERVABILITY_NAMESPACE}/grafana"; do
  namespace="${deployment%%/*}"
  name="${deployment##*/}"
  kubectl rollout status "deployment/${name}" --namespace "${namespace}" --timeout=5m
done

agent_containers="$(
  kubectl get daemonset aws-node --namespace kube-system \
    --output=jsonpath='{.spec.template.spec.containers[*].name}'
)"
if [[ " ${agent_containers} " != *" aws-eks-nodeagent "* ]]; then
  echo "VPC CNI network-policy agent is not running in aws-node." >&2
  exit 1
fi

enforcement_mode="$(
  kubectl get daemonset aws-node --namespace kube-system --output=json | \
    jq -r '.spec.template.spec.containers[]
      | select(.name == "aws-node")
      | .env[]?
      | select(.name == "NETWORK_POLICY_ENFORCING_MODE")
      | .value'
)"
if [[ "${enforcement_mode}" != "strict" ]]; then
  echo "VPC CNI network-policy mode is '${enforcement_mode}', expected strict." >&2
  exit 1
fi
echo "vpc-cni-network-policy: ok (strict)"

agent_enabled="$(
  kubectl get daemonset aws-node --namespace kube-system --output=json | \
    jq -r '.spec.template.spec.containers[]
      | select(.name == "aws-eks-nodeagent")
      | .args[]?
      | select(. == "--enable-network-policy=true")'
)"
if [[ "${agent_enabled}" != "--enable-network-policy=true" ]]; then
  echo "VPC CNI network-policy agent is present but not enabled." >&2
  exit 1
fi
echo "vpc-cni-network-policy-agent: ok (enabled)"

power_ip="$(kubectl get service power-sim --namespace "${OT_NAMESPACE}" \
  --output=jsonpath='{.spec.clusterIP}')"
influx_ip="$(kubectl get service influxdb --namespace "${OBSERVABILITY_NAMESPACE}" \
  --output=jsonpath='{.spec.clusterIP}')"
probe_image="$(kubectl get deployment modbus-ingestor \
  --namespace "${INGESTION_NAMESPACE}" \
  --output=jsonpath='{.spec.template.spec.containers[0].image}')"

probe() {
  local namespace="$1"
  local name="$2"
  local labels="$3"
  local host="$4"
  local port="$5"
  local expectation="$6"
  local code

  kubectl delete pod "${name}" --namespace "${namespace}" \
    --ignore-not-found --wait=true >/dev/null

  if [[ "${expectation}" == "allow" ]]; then
    code='import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), 3).close()'
  else
    code='import socket,sys
try:
    socket.create_connection((sys.argv[1], int(sys.argv[2])), 3).close()
except OSError:
    raise SystemExit(0)
raise SystemExit(1)'
  fi

  kubectl run "${name}" --namespace "${namespace}" \
    --image="${probe_image}" --image-pull-policy=IfNotPresent \
    --restart=Never --labels="${labels}" \
    --command -- python -c "${code}" "${host}" "${port}" >/dev/null

  local phase=""
  local attempt
  for attempt in $(seq 1 30); do
    phase="$(kubectl get pod "${name}" --namespace "${namespace}" \
      --output=jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "${phase}" == "Succeeded" || "${phase}" == "Failed" ]] && break
    sleep 1
  done

  if [[ "${phase}" != "Succeeded" ]]; then
    kubectl describe pod "${name}" --namespace "${namespace}" >&2 || true
    kubectl logs "${name}" --namespace "${namespace}" >&2 || true
    echo "${name}: expected ${expectation}, pod phase was ${phase:-unknown}" >&2
    exit 1
  fi
  echo "${name}: ok (${expectation})"
  kubectl delete pod "${name}" --namespace "${namespace}" --wait=true >/dev/null
}

probe "${INGESTION_NAMESPACE}" allow-ingestor-power \
  "app.kubernetes.io/name=modbus-ingestor" "${power_ip}" 1502 allow
probe "${INGESTION_NAMESPACE}" deny-untrusted-power \
  "app.kubernetes.io/name=untrusted" "${power_ip}" 1502 deny
probe "${OBSERVABILITY_NAMESPACE}" deny-grafana-power \
  "app.kubernetes.io/name=grafana" "${power_ip}" 1502 deny
probe "${INGESTION_NAMESPACE}" allow-ingestor-influx \
  "app.kubernetes.io/name=modbus-ingestor" "${influx_ip}" 8086 allow
probe "${OBSERVABILITY_NAMESPACE}" allow-grafana-influx \
  "app.kubernetes.io/name=grafana" "${influx_ip}" 8086 allow
probe "${OT_NAMESPACE}" deny-power-influx \
  "app.kubernetes.io/name=power-sim" "${influx_ip}" 8086 deny
probe "${OBSERVABILITY_NAMESPACE}" deny-untrusted-influx \
  "app.kubernetes.io/name=untrusted" "${influx_ip}" 8086 deny

if ! kubectl logs deployment/modbus-ingestor \
  --namespace "${INGESTION_NAMESPACE}" --tail=200 | grep -q 'modbus_ingest_ok'; then
  echo "The real ingestor has not recorded a successful Modbus-to-Influx cycle." >&2
  exit 1
fi
echo "modbus-to-influx: ok"

forward_log_dir="$(mktemp -d)"
influx_pid=""
grafana_pid=""
cleanup() {
  [[ -z "${influx_pid}" ]] || kill "${influx_pid}" 2>/dev/null || true
  [[ -z "${grafana_pid}" ]] || kill "${grafana_pid}" 2>/dev/null || true
  rm -rf "${forward_log_dir}"
}
trap cleanup EXIT

kubectl port-forward --address 127.0.0.1 \
  --namespace "${OBSERVABILITY_NAMESPACE}" service/influxdb 8086:8086 \
  >"${forward_log_dir}/influx.log" 2>&1 &
influx_pid=$!
kubectl port-forward --address 127.0.0.1 \
  --namespace "${OBSERVABILITY_NAMESPACE}" service/grafana 3000:3000 \
  >"${forward_log_dir}/grafana.log" 2>&1 &
grafana_pid=$!

python3 - <<'PY'
import socket
import time

for port in (8086, 3000):
    for _ in range(30):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                break
        except OSError:
            time.sleep(1)
    else:
        raise SystemExit(f"port-forward did not open 127.0.0.1:{port}")
PY

GRIDGUARD_SMOKE_SOURCE=modbus_tcp python3 scripts/smoke/local_pipeline_smoke.py
python3 scripts/smoke/grafana_dashboard_smoke.py
echo "Kubernetes segmentation and end-to-end smoke test passed."
