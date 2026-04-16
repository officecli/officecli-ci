# officecli-ci

Public GitHub Actions orchestration for the private `officecli/officecli` repository.

This repository stores workflow definitions only. It does not mirror private source code.

## Security model

- Private source is checked out from `officecli/officecli` at runtime.
- Source access uses the `SOURCE_REPO_TOKEN` Actions secret.
- No production or release secret is copied here automatically.
- Release and inspection workflows stay gated until the required secrets are added manually.

## Required secrets

- `SOURCE_REPO_TOKEN`: read access to `officecli/officecli`

Optional secrets for gated workflows:

- `PUBLIC_DIST_REPO_TOKEN`
- `PLATFORM_LICENSE_PROOF_SEED`
- `CLI_EMBEDDED_PUBLISH_AUTH_KEY`
- `OFFICE_CLI_LLM_BASE_URL`
- `OFFICE_CLI_LLM_API_KEY`
- `OFFICE_CLI_LICENSE_API_KEY`
- `OFFICE_CLI_PUBLISH_API_KEY`
- `CLI_E2E_EMAIL_SMTP_HOST`
- `CLI_E2E_EMAIL_SMTP_USERNAME`
- `CLI_E2E_EMAIL_SMTP_PASSWORD`
- `DINGTALK_WEBHOOK`
- `INSPECTION_FINGERPRINT_HASH`
- `INSPECTION_API_KEY`
- `INSPECTION_BLOCKED_API_KEY`
- `INSPECTION_USER_ID`

## Optional variables

- `CLI_PUBLISH_LATEST_ENABLED`
- `CLI_INSTALLED_E2E_ENABLED`
- `CLI_E2E_DIST_REPO`
- `CLI_INSTALLED_E2E_DEFAULT_VERSION`
- `CLI_INSTALLED_E2E_DEFAULT_SUITE`
- `CLI_EMBEDDED_PUBLISH_BASE_URL`
- `CLI_EMBEDDED_PUBLISH_AUTH_KEY_ID`
- `HOMEBREW_TAP_REPO`
- `HOMEBREW_TAP_DEFAULT_BRANCH`
- `INSPECTION_SITE_BASE_URL`
- `INSPECTION_PLATFORM_BASE_URL`
- `OFFICE_CLI_LICENSE_BASE_URL`
- `OFFICE_CLI_LLM_MODEL`
- `OFFICE_CLI_LLM_REVIEW_MODEL`
