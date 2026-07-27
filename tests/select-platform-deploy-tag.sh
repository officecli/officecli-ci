#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
selector="${repo_root}/scripts/select-platform-deploy-tag.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

assert_selection() {
  local name="$1"
  local expected="$2"
  local state_content="$3"
  local candidates="$4"
  local manual_tag="${5:-}"
  local state_file="${temp_dir}/${name}.state"
  local actual

  printf '%s' "${state_content}" > "${state_file}"
  actual="$(printf '%s' "${candidates}" | "${selector}" "${state_file}" "${manual_tag}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL %s\nexpected:\n%s\nactual:\n%s\n' "${name}" "${expected}" "${actual}" >&2
    return 1
  fi
  printf 'PASS %s\n' "${name}"
}

assert_selection \
  "selects-newest-unprocessed-tag" \
  $'release_tag=v0.2.0-prod-20260727-1\nshould_run=true' \
  $'v0.2.0-prod-20260726-1\n' \
  $'v0.2.0-prod-20260727-1\nv0.2.0-prod-20260726-1\n'

assert_selection \
  "ignores-older-gap-when-newest-is-processed" \
  $'release_tag=\nshould_run=false' \
  $'v0.2.0-prod-20260727-1\n' \
  $'v0.2.0-prod-20260727-1\nv0.2.0-prod-20260403-1\n'

assert_selection \
  "does-nothing-without-production-tags" \
  $'release_tag=\nshould_run=false' \
  '' \
  ''
