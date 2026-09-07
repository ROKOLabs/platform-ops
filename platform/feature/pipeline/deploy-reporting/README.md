# Deploy reporting adapter

The deploy reporting adapter records a successful deployment in Roko after a
delivery system finishes deploying it. Reporting does not fail the delivery job
unless strict mode is enabled.

The adapter sends the environment name and deployed commit SHA. It adds an
internal per-invocation identifier so retries do not create duplicate records.
It never deploys an application or infrastructure.

This version assumes that each Roko project uses a Git-based version control
system. The adapter identifies deployed work by its Git commit SHA.

## GitHub Actions

Add this step after the deployment step:

```yaml
- name: Report the deployment to Roko
  uses: ROKOLabs/platform-ops/platform/feature/pipeline/deploy-reporting/wrappers/github@v1
  with:
    url: https://platform.example.com/api/deploys
    token: ${{ secrets.ROKO_DEPLOY_TOKEN }}
    environment: prod
```

The `@v1` suffix selects the `v1` Git tag in the `platform-ops` repository.

The action uses `github.sha` as the commit. Set `strict: true` only when a failed
report should fail the workflow step.

## Core scripts

The cores accept the same options. Run the POSIX shell core with:

```sh
./platform/feature/pipeline/deploy-reporting/core/roko-adapter.sh \
  --url URL --token TOKEN --environment NAME [--strict]
```

Run the PowerShell core with:

```powershell
./platform/feature/pipeline/deploy-reporting/core/roko-adapter.ps1 `
  --url URL --token TOKEN --environment NAME [--strict]
```

Each flag overrides its matching environment variable:

| Flag | Environment variable |
| --- | --- |
| `--url` | `ROKO_ENDPOINT_URL` |
| `--token` | `ROKO_DEPLOY_TOKEN` |
| `--environment` | `ROKO_ENVIRONMENT` |
| `--strict` | `ROKO_STRICT=1` |

The core reads the commit from `ROKO_SHA`. When that variable is empty, it uses
`git rev-parse HEAD`. Each invocation generates one deployment ID and reuses it
for every retry. It makes up to five attempts for network errors, HTTP 429, and
HTTP 5xx responses. Other HTTP errors are not retried.

Without strict mode, every reporting outcome exits with code 0. With strict
mode, missing input exits 2, an HTTP or network failure exits 3, and a missing
`curl` command in the shell core exits 4.
