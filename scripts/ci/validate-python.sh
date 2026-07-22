#!/usr/bin/env bash
set -euo pipefail

mapfile -t python_files < <(
  git ls-files --cached --others --exclude-standard -- \
    '*.py' \
    ':!:**/.venv/**' \
    ':!:venv/**'
)

existing_python_files=()
for python_file in "${python_files[@]}"; do
  [[ -f "${python_file}" ]] || continue
  existing_python_files+=("${python_file}")
done
python_files=("${existing_python_files[@]}")

if [[ "${#python_files[@]}" -eq 0 ]]; then
  echo "No Python files found; skipping Python validation."
  exit 0
fi

if [[ "${CI:-false}" == "true" ]]; then
  python -m pip install --upgrade pip
fi

mapfile -t requirement_files < <(
  git ls-files \
    --cached \
    --others \
    --exclude-standard \
    -- \
    'requirements*.txt' \
    '*/requirements*.txt'
)

for requirements_file in "${requirement_files[@]}"; do
  [[ -f "${requirements_file}" ]] || continue
  if [[ "${CI:-false}" == "true" || "${GRIDGUARD_INSTALL_PYTHON_DEPS:-0}" == "1" ]]; then
    python -m pip install -r "${requirements_file}"
  else
    echo "Skipping ${requirements_file}; set GRIDGUARD_INSTALL_PYTHON_DEPS=1 to install locally."
  fi
done

ensure_python_module() {
  local module_name="$1"
  local package_name="${2:-$1}"

  if python -c "import ${module_name}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${CI:-false}" == "true" ]]; then
    python -m pip install "${package_name}"
    return 0
  fi

  echo "${package_name} is not installed locally; skipping ${package_name}-based checks."
  return 1
}

python -m compileall -q "${python_files[@]}"

if ensure_python_module ruff ruff; then
  python -m ruff check "${python_files[@]}"
fi

if ensure_python_module bandit bandit; then
  python -m bandit -r . -x '*/tests/*,*/test_*,.git,.venv,venv'
fi

mapfile -t test_files < <(
  git ls-files --cached --others --exclude-standard -- \
    '*test*.py' \
    'tests/**/*.py' \
    '*/tests/**/*.py'
)

existing_test_files=()
for test_file in "${test_files[@]}"; do
  [[ -f "${test_file}" ]] || continue
  existing_test_files+=("${test_file}")
done
test_files=("${existing_test_files[@]}")

if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "No Python tests found; skipping pytest."
  exit 0
fi

if ensure_python_module pytest pytest; then
  python -m pytest
else
  python -m unittest discover
fi
