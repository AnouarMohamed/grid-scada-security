#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

checks=(
  validate-repo-hygiene.sh
  validate-docs.sh
  validate-python.sh
  validate-modbus-contracts.sh
  validate-terraform.sh
  validate-docker.sh
)

for check in "${checks[@]}"; do
  echo "==> ${check}"
  bash "${SCRIPT_DIR}/${check}"
done
