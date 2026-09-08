# Roko platform operations

Versioned operational components used by the Roko platform and by delivery
systems that integrate with it. This repository publishes; it does not apply
Terraform and it does not deploy the Roko platform. A deployment consumes what
is here from its own repository, with its own credentials and its own state.

The repository is public, so every component is fetched without a token.

## Components

| Component | What it is |
| --- | --- |
| [Terraform modules](platform/deploy/tf/README.md) | One composed module per cloud, `modules/aws` and `modules/azure`. A deployment sets one `source` and one version, and that module owns its whole deployment: network, cluster, database, object storage, registries, budget, secrets, and the Helm releases that run the platform. The linked setup guide takes a new deployment from an empty account to a serving hostname; [`examples/aws`](platform/deploy/tf/examples/aws) and [`examples/azure`](platform/deploy/tf/examples/azure) are complete roots to copy. |
| [Deploy reporting adapter](platform/feature/pipeline/deploy-reporting/README.md) | A shell and PowerShell adapter, wrapped as a GitHub Action, that reports a finished deployment back to the platform. |

## Versioning

Every component is pinned by git tag, and there is one tag sequence for the
repository. A tag is a bare semantic version, `0.0.0` format.

```hcl
# Terraform
source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"
```

```yaml
# GitHub Actions
uses: ROKOLabs/platform-ops/platform/feature/pipeline/deploy-reporting/wrappers/github@0.0.1
```

For the Terraform modules the tag means something stricter: it is the
`ROKOLabs/platform` release the module deploys. `modules/<provider>/version.tf`
holds that release string, and CI refuses a tag that disagrees with it, so a
deployment pinned at `?ref=X.Y.Z` gets the infrastructure, the chart and the
`docker.io/rokoplatform/*` images of release `X.Y.Z` together.

## Checks

Every pull request runs both workflows. Neither has a `paths:` filter, because a
filter stops a workflow from triggering, and a required check that never runs
blocks nothing.

| Workflow | What it gates |
| --- | --- |
| [`format`](.github/workflows/format.yml) | `terraform fmt` across the tree, and the yamlfmt, shfmt and dprint hooks declared in `.pre-commit-config.yaml`. |
| [`terraform`](.github/workflows/terraform.yml) | Every module initialises and validates on its own; no module carries a backend block, a provider configuration, a lock file, a state file, a plan file, `kubernetes_manifest`, `aws_eks_cluster_auth`, a DNS resource or a hard-coded address range; and on a tag, that `version.tf` agrees with it. |

Run the formatters locally with `pre-commit install`, or once with
`pre-commit run --all-files`.
