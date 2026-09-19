#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to the authenticated non-root AWS CLI profile.}"
: "${EVIDENCE_START_TIME:?Set EVIDENCE_START_TIME to the UTC experiment start, for example 2026-09-20T09:00:00Z.}"

readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly EXPECTED_AWS_ACCOUNT_ID="${EXPECTED_AWS_ACCOUNT_ID:-227755136916}"
readonly GRIDGUARD_ENVIRONMENT="${GRIDGUARD_ENVIRONMENT:-aws-sandbox}"
readonly EVIDENCE_END_TIME="${EVIDENCE_END_TIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
readonly NAME_PREFIX="gridguard-${GRIDGUARD_ENVIRONMENT}"
readonly CLUSTER_NAME="${NAME_PREFIX}"
readonly OUTPUT_ROOT="${EVIDENCE_OUTPUT_ROOT:-tmp/aws-runtime-evidence}"
readonly RUN_ID="${EVIDENCE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
readonly OUTPUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"
readonly ERRORS_FILE="${OUTPUT_DIR}/collection-errors.tsv"
readonly -a SERVICES=(power-sim modbus-ingestor influxdb grafana)

export AWS_PAGER=""
umask 077

for command in aws jq git sha256sum tar date; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'ERROR Required command not found: %s\n' "${command}" >&2
    exit 2
  fi
done

if ! start_epoch="$(date -u -d "${EVIDENCE_START_TIME}" +%s 2>/dev/null)"; then
  printf 'ERROR Invalid EVIDENCE_START_TIME: %s\n' "${EVIDENCE_START_TIME}" >&2
  exit 2
fi
if ! end_epoch="$(date -u -d "${EVIDENCE_END_TIME}" +%s 2>/dev/null)"; then
  printf 'ERROR Invalid EVIDENCE_END_TIME: %s\n' "${EVIDENCE_END_TIME}" >&2
  exit 2
fi
if (( start_epoch >= end_epoch )); then
  printf 'ERROR Evidence start must be before evidence end.\n' >&2
  exit 2
fi

readonly START_EPOCH_MS="$((start_epoch * 1000))"
readonly END_EPOCH_MS="$((end_epoch * 1000))"
mkdir -p "${OUTPUT_DIR}"/{aws,logs,metadata}
: >"${ERRORS_FILE}"

aws_read() {
  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --no-cli-pager "$@"
}

capture() {
  local output="$1"
  local label="$2"
  shift 2

  local error_file="${output}.stderr"
  if aws_read "$@" --output json >"${output}" 2>"${error_file}"; then
    rm -f "${error_file}"
    printf 'CAPTURED %s\n' "${label}"
  else
    printf '%s\t%s\n' "${label}" "$(tr '\n' ' ' <"${error_file}")" >>"${ERRORS_FILE}"
    jq -n --arg label "${label}" --arg error "$(<"${error_file}")" \
      '{collection_status:"error", label:$label, error:$error}' >"${output}"
    rm -f "${error_file}"
    printf 'WARN     %s (recorded in collection-errors.tsv)\n' "${label}" >&2
  fi
}

identity_json="$(aws_read sts get-caller-identity --output json)"
account_id="$(jq -r '.Account' <<<"${identity_json}")"
principal_arn="$(jq -r '.Arn' <<<"${identity_json}")"

if [[ "${account_id}" != "${EXPECTED_AWS_ACCOUNT_ID}" ]]; then
  printf 'ERROR Expected AWS account %s, authenticated to %s.\n' \
    "${EXPECTED_AWS_ACCOUNT_ID}" "${account_id}" >&2
  exit 3
fi
if [[ "${principal_arn}" == *":root" ]]; then
  printf 'ERROR Refusing to collect evidence with root credentials.\n' >&2
  exit 3
fi

jq --arg region "${AWS_REGION}" --arg profile "${AWS_PROFILE}" \
  '. + {Region:$region, ProfileName:$profile}' <<<"${identity_json}" \
  >"${OUTPUT_DIR}/metadata/caller-identity.json"
aws --version >"${OUTPUT_DIR}/metadata/aws-cli-version.txt" 2>&1
git rev-parse HEAD >"${OUTPUT_DIR}/metadata/git-commit.txt"
git status --short >"${OUTPUT_DIR}/metadata/git-status.txt"

capture "${OUTPUT_DIR}/aws/ecs-cluster.json" "ECS cluster" \
  ecs describe-clusters --clusters "${CLUSTER_NAME}" --include ATTACHMENTS SETTINGS STATISTICS TAGS
capture "${OUTPUT_DIR}/aws/ecs-services.json" "ECS services" \
  ecs describe-services --cluster "${CLUSTER_NAME}" --services "${SERVICES[@]}" --include TAGS

capture "${OUTPUT_DIR}/aws/ecs-running-task-list.json" "running ECS task list" \
  ecs list-tasks --cluster "${CLUSTER_NAME}" --desired-status RUNNING
mapfile -t task_arns < <(jq -r '.taskArns[]?' \
  "${OUTPUT_DIR}/aws/ecs-running-task-list.json" | head -n 100)
if ((${#task_arns[@]} > 0)); then
  capture "${OUTPUT_DIR}/aws/ecs-running-tasks.json" "running ECS tasks" \
    ecs describe-tasks --cluster "${CLUSTER_NAME}" --tasks "${task_arns[@]}" --include TAGS
else
  jq -n '{tasks:[],failures:[]}' >"${OUTPUT_DIR}/aws/ecs-running-tasks.json"
fi

capture "${OUTPUT_DIR}/aws/ecs-stopped-task-list.json" "stopped ECS task list" \
  ecs list-tasks --cluster "${CLUSTER_NAME}" --desired-status STOPPED
mapfile -t stopped_task_arns < <(jq -r '.taskArns[]?' \
  "${OUTPUT_DIR}/aws/ecs-stopped-task-list.json" | head -n 100)
if ((${#stopped_task_arns[@]} > 0)); then
  capture "${OUTPUT_DIR}/aws/ecs-stopped-tasks.json" "stopped ECS tasks" \
    ecs describe-tasks --cluster "${CLUSTER_NAME}" --tasks "${stopped_task_arns[@]}" --include TAGS
else
  jq -n '{tasks:[],failures:[]}' >"${OUTPUT_DIR}/aws/ecs-stopped-tasks.json"
fi

for service in "${SERVICES[@]}"; do
  task_definition="$(jq -r --arg service "${service}" \
    '.services[]? | select(.serviceName == $service) | .taskDefinition' \
    "${OUTPUT_DIR}/aws/ecs-services.json" | head -n 1)"
  if [[ -n "${task_definition}" ]]; then
    capture "${OUTPUT_DIR}/aws/task-definition-${service}.json" \
      "task definition ${service}" ecs describe-task-definition \
      --task-definition "${task_definition}" --include TAGS
  fi
done

for service in "${SERVICES[@]}"; do
  repository="${NAME_PREFIX}/${service}"
  capture "${OUTPUT_DIR}/aws/ecr-${service}.json" "ECR metadata ${service}" \
    ecr describe-images --repository-name "${repository}" --filter tagStatus=ANY
done

capture "${OUTPUT_DIR}/aws/vpcs.json" "tagged VPC" ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=gridguard" "Name=tag:Environment,Values=${GRIDGUARD_ENVIRONMENT}"
capture "${OUTPUT_DIR}/aws/subnets.json" "tagged subnets" ec2 describe-subnets \
  --filters "Name=tag:Project,Values=gridguard" "Name=tag:Environment,Values=${GRIDGUARD_ENVIRONMENT}"
capture "${OUTPUT_DIR}/aws/route-tables.json" "tagged route tables" ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=gridguard" "Name=tag:Environment,Values=${GRIDGUARD_ENVIRONMENT}"
capture "${OUTPUT_DIR}/aws/security-groups.json" "tagged security groups" ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=gridguard" "Name=tag:Environment,Values=${GRIDGUARD_ENVIRONMENT}"
capture "${OUTPUT_DIR}/aws/vpc-endpoints.json" "tagged VPC endpoints" ec2 describe-vpc-endpoints \
  --filters "Name=tag:Project,Values=gridguard" "Name=tag:Environment,Values=${GRIDGUARD_ENVIRONMENT}"

capture "${OUTPUT_DIR}/aws/load-balancers.json" "GridGuard load balancer" \
  elbv2 describe-load-balancers --names "${NAME_PREFIX}-grafana"
capture "${OUTPUT_DIR}/aws/target-groups.json" "GridGuard target group" \
  elbv2 describe-target-groups --names "${NAME_PREFIX}-grafana"
target_group_arn="$(jq -r '.TargetGroups[0].TargetGroupArn // empty' \
  "${OUTPUT_DIR}/aws/target-groups.json")"
if [[ -n "${target_group_arn}" ]]; then
  capture "${OUTPUT_DIR}/aws/target-health.json" "Grafana target health" \
    elbv2 describe-target-health --target-group-arn "${target_group_arn}"
fi

for service in "${SERVICES[@]}"; do
  capture "${OUTPUT_DIR}/logs/${service}.json" "CloudWatch logs ${service}" \
    logs filter-log-events --log-group-name "/gridguard/${GRIDGUARD_ENVIRONMENT}/${service}" \
    --start-time "${START_EPOCH_MS}" --end-time "${END_EPOCH_MS}"
done
capture "${OUTPUT_DIR}/logs/vpc-flow.json" "VPC flow logs" \
  logs filter-log-events --log-group-name "/gridguard/${GRIDGUARD_ENVIRONMENT}/vpc-flow" \
  --start-time "${START_EPOCH_MS}" --end-time "${END_EPOCH_MS}"

jq -n \
  --arg schema_version "1.0" \
  --arg run_id "${RUN_ID}" \
  --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg start_time "$(date -u -d "@${start_epoch}" +%Y-%m-%dT%H:%M:%SZ)" \
  --arg end_time "$(date -u -d "@${end_epoch}" +%Y-%m-%dT%H:%M:%SZ)" \
  --arg account_id "${account_id}" \
  --arg region "${AWS_REGION}" \
  --arg principal_arn "${principal_arn}" \
  --arg git_commit "$(<"${OUTPUT_DIR}/metadata/git-commit.txt")" \
  --argjson collection_errors "$(wc -l <"${ERRORS_FILE}")" \
  '{schema_version:$schema_version,run_id:$run_id,collected_at:$collected_at,
    evidence_window:{start:$start_time,end:$end_time},aws:{account_id:$account_id,
    region:$region,principal_arn:$principal_arn},git_commit:$git_commit,
    collection_errors:$collection_errors,secret_values_collected:false}' \
  >"${OUTPUT_DIR}/manifest.json"

(
  cd "${OUTPUT_DIR}"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
)

archive_path="${OUTPUT_ROOT}/${RUN_ID}.tar.gz"
tar -czf "${archive_path}" -C "${OUTPUT_ROOT}" "${RUN_ID}"
sha256sum "${archive_path}" >"${archive_path}.sha256"

printf '\nEvidence directory: %s\n' "${OUTPUT_DIR}"
printf 'Archive:            %s\n' "${archive_path}"
printf 'Archive checksum:   %s\n' "$(cut -d ' ' -f 1 <"${archive_path}.sha256")"
if [[ -s "${ERRORS_FILE}" ]]; then
  printf 'WARNING: collection completed with recorded gaps; review %s.\n' "${ERRORS_FILE}" >&2
  exit 1
fi
printf 'Collection complete with no recorded API gaps.\n'
