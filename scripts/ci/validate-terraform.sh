#!/usr/bin/env bash
set -euo pipefail

mapfile -t terraform_files < <(
  git ls-files --cached --others --exclude-standard -- '*.tf' '*.tf.json'
)

if [[ "${#terraform_files[@]}" -eq 0 ]]; then
  echo "No Terraform files found; skipping Terraform validation."
  exit 0
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "::error::Terraform files exist, but terraform is not installed."
  exit 1
fi

terraform fmt -check -recursive

declare -A seen_dirs=()
terraform_dirs=()

for file in "${terraform_files[@]}"; do
  dir="$(dirname "${file}")"
  if [[ -z "${seen_dirs[${dir}]+x}" ]]; then
    seen_dirs["${dir}"]=1
    terraform_dirs+=("${dir}")
  fi
done

for dir in "${terraform_dirs[@]}"; do
  terraform -chdir="${dir}" init -backend=false -input=false
  terraform -chdir="${dir}" validate
done
