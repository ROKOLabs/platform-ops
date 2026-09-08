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

Pin by tag. The tag is the `ROKOLabs/platform` release it deploys.

```hcl
source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"
```
