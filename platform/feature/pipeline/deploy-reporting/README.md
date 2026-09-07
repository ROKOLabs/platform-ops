# Deploy reporting adapter

The deploy reporting adapter records a successful deployment in Roko after a
delivery system finishes deploying it. Reporting does not fail the delivery job
unless strict mode is enabled.

The adapter sends only the environment name, deployed commit SHA, and optional
deployment attempt id. It never deploys an application or infrastructure.

## GitHub Actions

Add this step after the deployment step:

```yaml
- name: Report the deployment to Roko
  uses: ROKOLabs/platform-ops/platform/feature/pipeline/deploy-reporting/wrappers/github@<COMMIT_SHA>
  with:
    url: https://platform.example.com/api/deploys
    token: ${{ secrets.ROKO_DEPLOY_TOKEN }}
    environment: prod
```

Replace `<COMMIT_SHA>` with the commit containing the adapter. A later release
step can introduce a stable component tag.

The action uses `github.sha` as the commit and
`github.run_id-github.run_attempt` as the deployment id. Set the optional `sha`
or `deploy-id` input to override either value. Set `strict: true` only when a
failed report should fail the workflow step.

## Core scripts

The POSIX shell and PowerShell cores use the same command:

```text
deploy --url URL --token TOKEN --environment NAME [--sha SHA] [--deploy-id ID] [--strict]
```

Each flag overrides its matching environment variable:

| Flag | Environment variable |
| --- | --- |
| `--url` | `ROKO_ENDPOINT_URL` |
| `--token` | `ROKO_DEPLOY_TOKEN` |
| `--environment` | `ROKO_ENVIRONMENT` |
| `--sha` | `ROKO_SHA` |
| `--deploy-id` | `ROKO_DEPLOY_ID` |
| `--strict` | `ROKO_STRICT=1` |

When no SHA is provided, the core uses `git rev-parse HEAD`. It retries network
errors, HTTP 429, and HTTP 5xx responses three times. Other HTTP errors are not
retried.

Without strict mode, every reporting outcome exits with code 0. With strict
mode, missing input exits 2, an HTTP or network failure exits 3, and a missing
`curl` command in the shell core exits 4.
