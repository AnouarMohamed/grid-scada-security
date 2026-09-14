#!/usr/bin/env bash
set -euo pipefail

mapfile -t terraform_files < <(
  git ls-files --cached --others --exclude-standard -- '*.tf' '*.tf.json'
)

existing_terraform_files=()
for terraform_file in "${terraform_files[@]}"; do
  [[ -f "${terraform_file}" ]] || continue
  existing_terraform_files+=("${terraform_file}")
done
terraform_files=("${existing_terraform_files[@]}")

if [[ "${#terraform_files[@]}" -eq 0 ]]; then
  echo "No Terraform files found; skipping Terraform validation."
  exit 0
fi

if ! command -v terraform >/dev/null 2>&1; then
  if [[ "${CI:-false}" == "true" ]]; then
    echo "::error::Terraform files exist, but terraform is not installed."
    exit 1
  fi

  echo "Terraform files found, but terraform is not installed locally; skipping Terraform validation."
  exit 0
fi

terraform fmt -check -recursive

terraform_data_root="$(mktemp -d)"
trap 'rm -rf "${terraform_data_root}"' EXIT

declare -A seen_dirs=()
terraform_dirs=()

for file in "${terraform_files[@]}"; do
  dir="$(dirname "${file}")"
  if [[ -z "${seen_dirs[${dir}]+x}" ]]; then
    seen_dirs["${dir}"]=1
    terraform_dirs+=("${dir}")
  fi
done

for index in "${!terraform_dirs[@]}"; do
  dir="${terraform_dirs[${index}]}"
  data_dir="${terraform_data_root}/${index}"
  mkdir -p "${data_dir}"

  TF_DATA_DIR="${data_dir}" terraform -chdir="${dir}" init -backend=false -input=false
  TF_DATA_DIR="${data_dir}" terraform -chdir="${dir}" validate

  if [[ -d "${dir}/tests" ]]; then
    TF_DATA_DIR="${data_dir}" terraform -chdir="${dir}" test
  fi
done
