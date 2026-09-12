#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to the non-root AWS CLI profile to validate.}"

readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly TEMPLATE="${REPOSITORY_ROOT}/infra/cloudformation/bootstrap/foundation-deployment-role.yaml"
export AWS_PAGER=""

for command in aws jq; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'ERROR Required command not found: %s\n' "${command}" >&2
    exit 2
  fi
done

principal_arn="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" \
  --no-cli-pager sts get-caller-identity --query Arn --output text)"
if [[ "${principal_arn}" == *":root" ]]; then
  printf 'ERROR Refusing to validate with root credentials.\n' >&2
  exit 1
fi

validation_json="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" \
  --no-cli-pager cloudformation validate-template \
  --template-body "file://${TEMPLATE}" --output json)"

jq -e '
  (.Capabilities | index("CAPABILITY_NAMED_IAM")) != null and
  ([.Parameters[].ParameterKey] | sort) ==
    (["DeploymentRoleName", "OperatorUserName", "StateAccessPolicyArn"] | sort)
' >/dev/null <<<"${validation_json}"

printf 'PASS  CloudFormation accepted %s\n' "${TEMPLATE#"${REPOSITORY_ROOT}/"}"
printf 'PASS  Named-IAM capability and three expected parameters are declared\n'
printf 'PASS  Validation made no AWS resource changes\n'
