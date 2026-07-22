#!/usr/bin/env bash
set -euo pipefail

dockerfiles=()
compose_files=()

while IFS= read -r file; do
  [[ -f "${file}" ]] || continue

  case "${file}" in
    Dockerfile|*/Dockerfile|Dockerfile.*|*/Dockerfile.*)
      dockerfiles+=("${file}")
      ;;
    docker-compose.yml|*/docker-compose.yml|docker-compose.yaml|*/docker-compose.yaml|compose.yml|*/compose.yml|compose.yaml|*/compose.yaml)
      compose_files+=("${file}")
      ;;
  esac
done < <(git ls-files --cached --others --exclude-standard)

if [[ "${#dockerfiles[@]}" -eq 0 && "${#compose_files[@]}" -eq 0 ]]; then
  echo "No Dockerfiles or Compose files found; skipping Docker validation."
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  if [[ "${CI:-false}" == "true" ]]; then
    echo "::error::Docker files exist, but docker is not installed."
    exit 1
  fi

  echo "Docker files found, but docker is not installed locally; skipping Docker validation."
  exit 0
fi

for compose_file in "${compose_files[@]}"; do
  docker compose -f "${compose_file}" config --quiet
done

if [[ "${CI:-false}" != "true" && "${GRIDGUARD_DOCKER_BUILD:-0}" != "1" ]]; then
  echo "Docker build skipped locally. Set GRIDGUARD_DOCKER_BUILD=1 to build images."
  exit 0
fi

for dockerfile in "${dockerfiles[@]}"; do
  context_dir="$(dirname "${dockerfile}")"
  tag="gridguard-ci-$(echo "${dockerfile}" | tr '[:upper:]' '[:lower:]' | tr '/.' '--' | tr -cd '[:alnum:]-')"
  docker build --pull --file "${dockerfile}" --tag "${tag}" "${context_dir}"
done
