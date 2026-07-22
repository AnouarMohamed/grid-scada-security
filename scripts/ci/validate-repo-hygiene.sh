#!/usr/bin/env bash
set -euo pipefail

failed=0

mapfile -d '' tracked_files < <(git ls-files -z --cached --others --exclude-standard)

for file in "${tracked_files[@]}"; do
  [[ -f "${file}" ]] || continue

  if ! LC_ALL=C grep -Iq . "${file}" && [[ -s "${file}" ]]; then
    continue
  fi

  if LC_ALL=C grep -n $'\r' "${file}" >/tmp/gridguard-crlf-check 2>/dev/null; then
    while IFS=: read -r line _; do
      echo "::error file=${file},line=${line}::CRLF line ending found"
    done </tmp/gridguard-crlf-check
    failed=1
  fi

  if LC_ALL=C grep -nE '[[:blank:]]$' "${file}" >/tmp/gridguard-trailing-space-check 2>/dev/null; then
    while IFS=: read -r line _; do
      echo "::error file=${file},line=${line}::Trailing whitespace found"
    done </tmp/gridguard-trailing-space-check
    failed=1
  fi

  if [[ -s "${file}" ]] && [[ "$(tail -c 1 "${file}" | wc -l)" -eq 0 ]]; then
    echo "::error file=${file}::Missing final newline"
    failed=1
  fi
done

if ! git check-ignore -q .env; then
  echo "::error::.env is not ignored at the repository root"
  failed=1
fi

exit "${failed}"
