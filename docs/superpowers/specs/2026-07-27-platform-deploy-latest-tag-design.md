# Platform Deploy Latest-Tag Selection Design

## Problem

The scheduled `Platform Deploy` workflow currently scans production tags from newest to oldest and deploys the first tag missing from `.state/platform-deploy-tags.txt`. Once all recent tags have been recorded, this turns historical gaps into deployment candidates.

That behavior repeatedly selects `v0.2.0-prod-20260403-1`. The tag is obsolete and its source tests fail under the workflow's production environment, so every scheduled run is blocked before deployment. Retrying or changing the current source branch cannot fix the failure because the workflow checks out the historical tag.

## Goals

- Scheduled runs consider only the newest `v*-prod-*` tag.
- If the newest production tag is already recorded, the scheduled run exits without deploying anything.
- If the newest production tag is not recorded, the scheduled run deploys that tag.
- Manual `workflow_dispatch` runs keep accepting an explicitly requested tag, including a historical tag used for rollback or a deliberate retry.
- Tag-selection behavior is covered by an automated regression test that does not require GitHub Actions or network access.

## Non-Goals

- Do not change the platform build, test, Kubernetes deployment, health-check, or processed-state persistence steps.
- Do not mark failed tags as processed.
- Do not remove historical entries from `.state/platform-deploy-tags.txt`.
- Do not change the separate CLI release workflow.
- Do not change `APP_ENV` or weaken production configuration validation.

## Considered Approaches

### 1. Select only the newest production tag and test the selector (recommended)

Move the tag-selection decision into a small shell script. Scheduled runs pass the newest production tag and the processed-state file to the script. Manual runs pass the requested tag. The workflow consumes the script's `release_tag` and `should_run` outputs.

This directly models the intended release policy, prevents historical backfill, and creates a stable test seam for the workflow logic.

### 2. Keep the logic inline in YAML

The inline loop could be replaced with `head -n 1` plus one processed-state check. This is a smaller diff, but the regression would be difficult to test without parsing or executing embedded YAML shell, making the same bug easier to reintroduce.

### 3. Record the failing historical tag as processed

Adding the old tag to the state file would unblock the next run temporarily, but any other historical gap could become the next candidate. It treats one symptom and preserves the faulty backfill policy.

## Design

### Selector interface

Create `scripts/select-platform-deploy-tag.sh` with this command-line interface:

```text
scripts/select-platform-deploy-tag.sh <state-file> [manual-release-tag]
```

The script reads candidate production tags from standard input, ordered newest first. It writes GitHub Actions-compatible key/value pairs to standard output:

```text
release_tag=<selected tag or empty>
should_run=<true or false>
```

Behavior:

1. When `manual-release-tag` is non-empty, normalize it to start with `v`, select it, and return `should_run=true`. The workflow remains responsible for verifying that the tag resolves to a commit in the source repository.
2. Otherwise, read only the first non-empty production-tag candidate from standard input.
3. If there is no candidate, return an empty tag and `should_run=false`.
4. If the newest candidate already appears as an exact line in the state file, return an empty tag and `should_run=false`.
5. Otherwise select the newest candidate and return `should_run=true`.

The selector never scans older candidates after the newest candidate has been evaluated.

### Workflow integration

Update `.github/workflows/platform-deploy.yml` so the resolve step:

1. Fetches source tags as it does today.
2. Ensures `.state/platform-deploy-tags.txt` exists.
3. Pipes `git tag --list 'v*-prod-*' --sort=-creatordate` into the selector.
4. Appends the selector output to `$GITHUB_OUTPUT`.
5. Validates an explicitly selected manual tag with `git rev-parse` after normalization.

All downstream `should_run` conditions and the successful-deployment state update remain unchanged.

### Error handling

- The selector uses strict shell mode and fails for missing required arguments or unreadable state.
- A manual tag that does not exist still fails during `git rev-parse`, matching current behavior.
- An empty production-tag set is a normal no-op scheduled run.
- A processed newest tag is a normal no-op scheduled run, even if older tags are absent from state.

## Tests

Create `tests/select-platform-deploy-tag.sh` using temporary state files and shell assertions. It covers:

- newest tag is unprocessed: selects only the newest tag;
- newest tag is processed while an older tag is missing: selects nothing, proving historical gaps are ignored;
- manual historical tag: normalizes and selects it regardless of processed state or newer candidates;
- no production tags: selects nothing;
- exact-line state matching: similar tag prefixes do not count as processed.

The focused test command is:

```bash
bash tests/select-platform-deploy-tag.sh
```

The workflow YAML also receives a syntax parse check using Ruby's built-in YAML parser with GitHub's `on` key handled as a string-compatible YAML 1.2 concern only if the repository's available parser supports it; the behavioral shell test is the authoritative regression check.

## Release and Verification

After merging the change to `officecli-ci/main`:

1. Dispatch `Platform Deploy` without `release_tag`, or observe the next scheduled run.
2. Verify the resolve step does not select `v0.2.0-prod-20260403-1` when the current newest production tag is already processed.
3. Verify the job reports no unprocessed latest production tag and performs no deployment.
4. On the next newly created production tag, verify the scheduled workflow selects that new tag and the normal deployment path runs.

This change does not alter the Kubernetes deployment strategy or live traffic handling. A no-op scheduled run has no user impact; a real new-tag deployment retains the workflow's existing rollout behavior.
