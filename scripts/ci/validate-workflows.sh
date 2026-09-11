#!/usr/bin/env bash
set -euo pipefail

readonly ACTIONLINT_VERSION="1.7.7"
readonly ACTIONLINT_LINUX_AMD64_SHA256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"
readonly ACTIONLINT_LINUX_ARM64_SHA256="401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0"

mapfile -t workflow_files < <(
  git ls-files --cached --others --exclude-standard -- \
    '.github/workflows/*.yml' \
    '.github/workflows/*.yaml'
)

if [[ "${#workflow_files[@]}" -eq 0 ]]; then
  echo "No GitHub Actions workflows found; skipping workflow validation."
  exit 0
fi

failed=0
for workflow_file in "${workflow_files[@]}"; do
  [[ -f "${workflow_file}" ]] || continue

  if grep -nE '^[[:space:]]*pull_request_target:' "${workflow_file}" >/dev/null; then
    echo "::error file=${workflow_file}::pull_request_target is prohibited by repository policy."
    failed=1
  fi

  if ! grep -qE '^permissions:' "${workflow_file}"; then
    echo "::error file=${workflow_file}::Workflow must declare top-level least-privilege permissions."
    failed=1
  fi

  while IFS=: read -r line_number declaration; do
    read -r action_ref _ <<< "${declaration#*uses:}"
    action_ref="${action_ref%\"}"
    action_ref="${action_ref#\"}"
    action_ref="${action_ref%\'}"
    action_ref="${action_ref#\'}"

    if [[ "${action_ref}" == ./* ]]; then
      continue
    fi
    if [[ "${action_ref}" =~ ^docker://.+@sha256:[0-9a-f]{64}$ ]]; then
      continue
    fi
    if [[ "${action_ref}" =~ ^[^[:space:]@]+@([0-9a-f]{40})$ ]]; then
      continue
    fi

    echo "::error file=${workflow_file},line=${line_number}::Action must use a full commit SHA: ${action_ref}"
    failed=1
  done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:' "${workflow_file}" || true)
done

if [[ "${failed}" -ne 0 ]]; then
  exit "${failed}"
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint -c .yamllint.yml "${workflow_files[@]}" compose.yaml
elif [[ "${CI:-false}" == "true" ]]; then
  echo "::error::yamllint is required but was not installed from requirements-dev.txt."
  exit 1
else
  echo "yamllint is not installed locally; skipping YAML style validation."
fi

actionlint_bin=""
if [[ "${CI:-false}" == "true" ]]; then
  case "$(uname -m)" in
    x86_64)
      actionlint_arch="amd64"
      actionlint_sha256="${ACTIONLINT_LINUX_AMD64_SHA256}"
      ;;
    aarch64|arm64)
      actionlint_arch="arm64"
      actionlint_sha256="${ACTIONLINT_LINUX_ARM64_SHA256}"
      ;;
    *)
      echo "::error::Unsupported actionlint architecture: $(uname -m)"
      exit 1
      ;;
  esac

  actionlint_dir="${RUNNER_TEMP}/actionlint-${ACTIONLINT_VERSION}"
  actionlint_archive="${actionlint_dir}.tar.gz"
  mkdir -p "${actionlint_dir}"
  curl --fail --location --silent --show-error \
    --retry 3 \
    --output "${actionlint_archive}" \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${actionlint_arch}.tar.gz"
  printf '%s  %s\n' "${actionlint_sha256}" "${actionlint_archive}" | sha256sum --check --strict
  tar -xzf "${actionlint_archive}" -C "${actionlint_dir}" actionlint
  actionlint_bin="${actionlint_dir}/actionlint"
else
  actionlint_bin="$(command -v actionlint || true)"
fi

if [[ -n "${actionlint_bin}" ]]; then
  "${actionlint_bin}"
else
  echo "actionlint is not installed locally; skipping semantic workflow validation."
fi
