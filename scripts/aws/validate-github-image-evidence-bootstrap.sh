#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to the non-root AWS CLI profile to validate.}"

readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly TEMPLATE="${REPOSITORY_ROOT}/infra/cloudformation/bootstrap/github-oidc-image-evidence-role.yaml"
export AWS_PAGER=""

for command in aws jq python; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    printf 'ERROR Required command not found: %s\n' "${command}" >&2
    exit 2
  fi
done

identity_json="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" \
  --no-cli-pager sts get-caller-identity --output json)"
principal_arn="$(jq -r '.Arn' <<<"${identity_json}")"
account_id="$(jq -r '.Account' <<<"${identity_json}")"
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
    ([
      "GitHubEnvironment",
      "GitHubOidcProviderArn",
      "GitHubRepository",
      "PolicyName",
      "RepositoryPrefix",
      "RoleName"
    ] | sort)
' >/dev/null <<<"${validation_json}"

resolved_policy="$(python - "${TEMPLATE}" "${AWS_REGION}" "${account_id}" <<'PY'
from pathlib import Path
import json
import sys
from typing import Any

import yaml


class CloudFormationLoader(yaml.SafeLoader):
    pass


def construct_intrinsic(
    loader: CloudFormationLoader,
    tag_suffix: str,
    node: yaml.Node,
) -> dict[str, Any]:
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node)
    else:
        value = loader.construct_mapping(node)
    return {f"!{tag_suffix}": value}


CloudFormationLoader.add_multi_constructor("!", construct_intrinsic)
template_path, region, account_id = sys.argv[1:]
template = yaml.load(
    Path(template_path).read_text(encoding="utf-8"),
    Loader=CloudFormationLoader,
)
values = {
    "AWS::Partition": "aws",
    "AWS::Region": region,
    "AWS::AccountId": account_id,
    "RepositoryPrefix": "gridguard-aws-sandbox",
}


def resolve(value: Any) -> Any:
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if not isinstance(value, dict):
        return value
    if set(value) == {"!Ref"}:
        return values[value["!Ref"]]
    if set(value) == {"!Sub"}:
        rendered = value["!Sub"]
        for key, replacement in values.items():
            rendered = rendered.replace("${" + key + "}", replacement)
        if "${" in rendered:
            raise SystemExit(f"unresolved CloudFormation substitution: {rendered}")
        return rendered
    return {key: resolve(item) for key, item in value.items()}


policy = template["Resources"]["GitHubImageEvidencePolicy"]["Properties"]
policy = policy["PolicyDocument"]
print(json.dumps(resolve(policy), separators=(",", ":")))
PY
)"

analysis_json="$(aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" \
  --no-cli-pager accessanalyzer validate-policy \
  --policy-type IDENTITY_POLICY \
  --policy-document "${resolved_policy}" \
  --output json)"
jq -e '.findings == []' >/dev/null <<<"${analysis_json}"

printf 'PASS  CloudFormation accepted %s\n' "${TEMPLATE#"${REPOSITORY_ROOT}/"}"
printf 'PASS  Named-IAM capability and six expected parameters are declared\n'
printf 'PASS  IAM Access Analyzer returned zero findings for the resolved policy\n'
printf 'PASS  Validation made no AWS resource changes\n'
