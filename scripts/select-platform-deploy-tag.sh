#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <state-file> [manual-release-tag]" >&2
  exit 64
fi

state_file="$1"
if [[ ! -r "${state_file}" ]]; then
  echo "state file is not readable: ${state_file}" >&2
  exit 66
fi

latest_tag=""
while IFS= read -r candidate; do
  if [[ -z "${latest_tag}" && -n "${candidate}" ]]; then
    latest_tag="${candidate}"
  fi
done

manual_tag="${2:-}"
release_tag=""
should_run=false

if [[ -n "${manual_tag}" ]]; then
  release_tag="${manual_tag}"
  if [[ "${release_tag}" != v* ]]; then
    release_tag="v${release_tag}"
  fi
  should_run=true
elif [[ -n "${latest_tag}" ]] && ! grep -Fxq -- "${latest_tag}" "${state_file}"; then
  release_tag="${latest_tag}"
  should_run=true
fi

printf 'release_tag=%s\n' "${release_tag}"
printf 'should_run=%s\n' "${should_run}"
