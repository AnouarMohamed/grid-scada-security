#!/usr/bin/env bash
set -euo pipefail

mapfile -t aws_scripts < <(find scripts/aws -maxdepth 1 -type f -name '*.sh' | sort)

if ((${#aws_scripts[@]} == 0)); then
  echo "No AWS shell scripts found; skipping AWS script validation."
  exit 0
fi

for script in "${aws_scripts[@]}"; do
  bash -n "${script}"
done

collector="scripts/aws/capture-runtime-evidence.sh"
if [[ ! -x "${collector}" ]]; then
  echo "::error file=${collector}::Runtime evidence collector must be executable."
  exit 1
fi

for forbidden_call in \
  'secretsmanager get-secret-value' \
  'ecs update-service' \
  'ecs run-task' \
  'ecs stop-task' \
  'cloudformation execute-change-set' \
  'terraform apply' \
  'terraform destroy'; do
  if grep -Fq "${forbidden_call}" "${collector}"; then
    echo "::error file=${collector}::Evidence collector contains forbidden call: ${forbidden_call}"
    exit 1
  fi
done

required_guards=(
  'EXPECTED_AWS_ACCOUNT_ID'
  'Refusing to collect evidence with root credentials'
  'secret_values_collected:false'
  'collection-errors.tsv'
  'SHA256SUMS'
)
for guard in "${required_guards[@]}"; do
  if ! grep -Fq "${guard}" "${collector}"; then
    echo "::error file=${collector}::Required evidence guard is missing: ${guard}"
    exit 1
  fi
done

echo "Validated ${#aws_scripts[@]} AWS shell scripts and the evidence safety guards."
