#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

checks=(
  validate-repo-hygiene.sh
  validate-docs.sh
  validate-cloudformation.sh
  validate-aws-scripts.sh
  validate-python.sh
  validate-workflows.sh
  validate-modbus-contracts.sh
  validate-kubernetes.py
  validate-terraform.sh
  validate-docker.sh
)

for check in "${checks[@]}"; do
  echo "==> ${check}"
  case "${check}" in
    *.py) python "${SCRIPT_DIR}/${check}" ;;
    *) bash "${SCRIPT_DIR}/${check}" ;;
  esac
done
