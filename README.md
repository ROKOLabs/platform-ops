# Roko platform operations

Versioned components the Roko platform and its delivery systems consume. This
repository publishes; it does not apply Terraform and it does not deploy the
platform. It is public, so nothing here needs a token to fetch.

## Components

| Component | What it is |
| --- | --- |
| [Terraform modules](platform/deploy/tf/README.md) | One composed module per cloud, `aws` and `azure`. A deployment sets one `source` and gets its whole infrastructure and the platform running on it. Start with the setup guide. |
| [Deploy reporting adapter](platform/feature/pipeline/deploy-reporting/README.md) | Reports a finished deployment back to the platform, wrapped as a GitHub Action. |

## Versioning

Pin by tag. The tag is the `ROKOLabs/platform` release it deploys. Use a semver tag like `0.0.22` to pin to an exact release, or use `latest` to follow the newest release automatically.

```hcl
# Pin to a semver release
source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.22"

# Follow the newest release automatically
source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=latest"
```

The `latest` tag moves when a new platform release is tagged. Clients using `latest` gain weekly updates on a schedule or can pin to a semver for consistency. The module's `platform_version` output always records the semver that `latest` resolved to, so a deployment shows the exact version it is running.
