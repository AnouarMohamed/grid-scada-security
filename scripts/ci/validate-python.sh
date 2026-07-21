#!/usr/bin/env bash
set -euo pipefail

mapfile -t python_files < <(
  git ls-files --cached --others --exclude-standard -- \
    '*.py' \
    ':!:**/.venv/**' \
    ':!:venv/**'
)

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
  python -m pip install -r "${requirements_file}"
done

python -m pip install bandit pytest ruff

python -m ruff check "${python_files[@]}"
python -m bandit -r gridguard -x '*/tests/*,*/test_*'

mapfile -t test_files < <(
  git ls-files --cached --others --exclude-standard -- \
    '*test*.py' \
    'tests/**/*.py' \
    '*/tests/**/*.py'
)

if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "No Python tests found; skipping pytest."
  exit 0
fi

python -m pytest
