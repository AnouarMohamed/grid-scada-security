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

python -m pip install --upgrade pip

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
  python -m pip install -r "${requirements_file}"
done

python -m pip install bandit pytest ruff

python -m ruff check "${python_files[@]}"
python -m bandit -r . -x '*/tests/*,*/test_*,.git,.venv,venv'

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

python -m pytest
