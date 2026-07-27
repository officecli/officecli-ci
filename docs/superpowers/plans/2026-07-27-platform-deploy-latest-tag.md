# Platform Deploy Latest-Tag Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop scheduled Platform Deploy runs from backfilling obsolete production-tag gaps while preserving explicit manual deployment of historical tags.

**Architecture:** Extract tag selection from the workflow's embedded shell into a focused Bash selector. The selector consumes newest-first production tags and the processed-state file, while the workflow remains responsible for fetching and validating Git tags. A dependency-free Bash regression test covers policy and workflow wiring.

**Tech Stack:** GitHub Actions YAML, Bash, Git, Ruby/Psych for YAML syntax validation

---

## File Structure

- Create `scripts/select-platform-deploy-tag.sh`: pure selection policy with GitHub Actions-compatible outputs.
- Create `tests/select-platform-deploy-tag.sh`: temporary-file behavioral tests plus workflow-wiring assertions.
- Modify `.github/workflows/platform-deploy.yml`: delegate selection to the script and keep Git tag validation in the workflow.

### Task 1: Scheduled latest-tag policy

**Files:**
- Create: `tests/select-platform-deploy-tag.sh`
- Create: `scripts/select-platform-deploy-tag.sh`

- [ ] **Step 1: Write the failing scheduled-selection test**

Create `tests/select-platform-deploy-tag.sh` with a small assertion harness and these three scheduled cases:

```bash
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
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
```

Expected: exit non-zero because `scripts/select-platform-deploy-tag.sh` does not exist.

- [ ] **Step 3: Implement the minimal scheduled selector**

Create `scripts/select-platform-deploy-tag.sh`:

```bash
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

release_tag=""
should_run=false
if [[ -n "${latest_tag}" ]] && ! grep -q -- "${latest_tag}" "${state_file}"; then
  release_tag="${latest_tag}"
  should_run=true
fi

printf 'release_tag=%s\n' "${release_tag}"
printf 'should_run=%s\n' "${should_run}"
```

Make both files executable:

```bash
chmod +x scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
```

- [ ] **Step 4: Run the scheduled-selection tests and verify GREEN**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
```

Expected: three `PASS` lines and exit 0.

- [ ] **Step 5: Commit the scheduled selector**

```bash
git add scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
git commit -m "test: cover latest platform deploy tag selection"
```

### Task 2: Manual tags and exact processed-state matching

**Files:**
- Modify: `tests/select-platform-deploy-tag.sh`
- Modify: `scripts/select-platform-deploy-tag.sh`

- [ ] **Step 1: Add failing manual and exact-match cases**

Append these assertions to `tests/select-platform-deploy-tag.sh`:

```bash
assert_selection \
  "manual-historical-tag-takes-priority" \
  $'release_tag=v0.2.0-prod-20260403-1\nshould_run=true' \
  $'v0.2.0-prod-20260403-1\n' \
  $'v0.2.0-prod-20260727-1\n' \
  '0.2.0-prod-20260403-1'

assert_selection \
  "processed-state-matches-exact-lines" \
  $'release_tag=v0.2.0-prod-20260727-1\nshould_run=true' \
  $'v0.2.0-prod-20260727-10\n' \
  $'v0.2.0-prod-20260727-1\n'
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
```

Expected: the manual case fails because the script ignores the manual argument, and the exact-match case fails because substring matching incorrectly treats the tag as processed.

- [ ] **Step 3: Implement manual priority and exact-line matching**

Replace the selection block in `scripts/select-platform-deploy-tag.sh` with:

```bash
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
```

- [ ] **Step 4: Run all selector tests and verify GREEN**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
```

Expected: five `PASS` lines and exit 0.

- [ ] **Step 5: Commit manual and exact-match behavior**

```bash
git add scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
git commit -m "fix: preserve manual platform deploy tags"
```

### Task 3: Wire the workflow to the tested selector

**Files:**
- Modify: `tests/select-platform-deploy-tag.sh`
- Modify: `.github/workflows/platform-deploy.yml`

- [ ] **Step 1: Add failing workflow-wiring assertions**

Append this structural check to `tests/select-platform-deploy-tag.sh`:

```bash
workflow_file="${repo_root}/.github/workflows/platform-deploy.yml"
if ! grep -Fq './scripts/select-platform-deploy-tag.sh' "${workflow_file}"; then
  echo 'FAIL workflow-does-not-call-selector' >&2
  exit 1
fi
if grep -Fq 'while IFS= read -r candidate' "${workflow_file}"; then
  echo 'FAIL workflow-still-backfills-historical-tags' >&2
  exit 1
fi
printf 'PASS workflow-uses-tested-selector\n'
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
```

Expected: selector behavior passes, then `FAIL workflow-does-not-call-selector` causes exit non-zero.

- [ ] **Step 3: Replace the inline backfill loop**

In `.github/workflows/platform-deploy.yml`, add the manual input to the resolve step's environment without interpolating it into shell source:

```yaml
        env:
          SOURCE_REPO_TOKEN: ${{ secrets.SOURCE_REPO_TOKEN }}
          MANUAL_RELEASE_TAG: ${{ inputs.release_tag }}
```

Then replace the release-tag selection block after `git -C source fetch --tags --force` with:

```bash
state_file="${GITHUB_WORKSPACE}/.state/platform-deploy-tags.txt"
mkdir -p "$(dirname "${state_file}")"
touch "${state_file}"
selection="$({
  git -C source tag --list 'v*-prod-*' --sort=-creatordate
} | ./scripts/select-platform-deploy-tag.sh "${state_file}" "${MANUAL_RELEASE_TAG}")"
printf '%s\n' "${selection}" >> "$GITHUB_OUTPUT"
release_tag="$(printf '%s\n' "${selection}" | sed -n 's/^release_tag=//p')"
if [ -n "${release_tag}" ]; then
  git -C source rev-parse "${release_tag}^{commit}" >/dev/null 2>&1
fi
```

Remove the old `release_tag` initialization, manual-normalization branch, historical-tag loop, `should_run` calculation, and direct output writes. Keep all later workflow steps unchanged.

- [ ] **Step 4: Run tests and workflow syntax checks**

Run:

```bash
bash tests/select-platform-deploy-tag.sh
bash -n scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/platform-deploy.yml'); puts 'PASS workflow-yaml-syntax'"
```

Expected: six test `PASS` lines, no shell syntax output, `PASS workflow-yaml-syntax`, and all commands exit 0.

- [ ] **Step 5: Commit workflow integration**

```bash
git add .github/workflows/platform-deploy.yml tests/select-platform-deploy-tag.sh
git commit -m "fix: stop platform deploy historical tag backfill"
```

### Task 4: Final verification and delivery evidence

**Files:**
- Verify: `.github/workflows/platform-deploy.yml`
- Verify: `scripts/select-platform-deploy-tag.sh`
- Verify: `tests/select-platform-deploy-tag.sh`

- [ ] **Step 1: Run the complete local verification suite**

```bash
bash tests/select-platform-deploy-tag.sh
bash -n scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/platform-deploy.yml'); puts 'PASS workflow-yaml-syntax'"
git diff --check origin/main...HEAD
```

Expected: all behavioral cases pass, syntax checks exit 0, and `git diff --check` emits no errors.

- [ ] **Step 2: Review the exact branch diff**

```bash
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- .github/workflows/platform-deploy.yml scripts/select-platform-deploy-tag.sh tests/select-platform-deploy-tag.sh
git status --short --branch
```

Expected: only the approved design/plan, selector, selector test, and Platform Deploy workflow are changed; the worktree is clean.

- [ ] **Step 3: Push the branch and observe CI**

```bash
git push -u origin fix/platform-deploy-latest-tag
gh run list --repo officecli/officecli-ci --branch fix/platform-deploy-latest-tag --limit 10
```

Expected: branch push succeeds and any branch-triggered checks are identified by exact run ID. Do not infer success from unrelated historical runs.

- [ ] **Step 4: After merge, verify scheduled/manual resolution behavior**

Dispatch without a tag or inspect the next scheduled `Platform Deploy` run. In the exact run's `Resolve target deploy tag` output, verify that a processed latest tag produces `should_run=false` and does not select `v0.2.0-prod-20260403-1`. When a new production tag exists, verify that exact latest tag is selected. Manual dispatch with an explicit historical tag remains available for deliberate rollback or retry.
