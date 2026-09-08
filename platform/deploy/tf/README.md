# Roko platform Terraform modules

One composed module per cloud. A deployment names one `source` and one version,
and that module owns the whole deployment: network, cluster, database, object
storage, registries, budget, secrets, and the Helm releases that run the
platform.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = "acme-prod"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b"]
  ingress_host = "acme.rokolabs.ai"
}
```

The repository is public, so the fetch needs no credential.

## Layout

```text
platform/deploy/tf/modules
├── aws
│   ├── main.tf          the composed entry point
│   ├── version.tf variables.tf outputs.tf versions.tf
│   ├── budget           cluster-baseline  ecr-repo   eks-cluster
│   └── external-secrets github-oidc       network    tf-backend
└── azure
    ├── main.tf          the composed entry point
    ├── version.tf variables.tf outputs.tf versions.tf
    ├── acr       aks       cluster-config  foundry  keyvault
    └── postgres  storage   vnet            workload-identity
```

`main.tf` sits beside the child directories, so `…//modules/aws` roots at the
composed module and every child resolves as `./network`, `./eks-cluster` and so
on. Each child is still a working module on its own, so a deployment with a
reason to bypass the composition can address `…/modules/aws/network` directly.
Nothing in the composition depends on that path being used.

Two children are in the tree but are not called by the composition:

| Child | Why it is separate |
| --- | --- |
| `aws/tf-backend` | It creates the S3 bucket the state lives in, so it cannot be inside the state it creates. Apply it once, with local state, before the first `terraform apply` of the composed module. |
| `aws/github-oidc` | A CI deploy role belongs to whoever runs CI, not to the deployment. A lane that builds its own images calls it from its own root. |

## Versioning

The module's version is the platform version. `modules/<provider>/version.tf`
holds the release string, the release tags this repository with that same string,
and CI refuses a tag that disagrees with the constant. A deployment pinned at
`?ref=X.Y.Z` gets the infrastructure, the chart, and the
`docker.io/rokoplatform/*` images of release `X.Y.Z`, with no second number to
reconcile.

`image_registry`, `image_names` and `image_tag` are the one supported override,
for a lane that builds its own images. No client deployment sets them.

## One apply

A deployment runs `terraform apply` once, including the first time. Ordering is
expressed as dependencies, not as a sequence a person runs by hand. Three rules
are what make that possible, and CI enforces the first two.

| Rule | Why |
| --- | --- |
| Authenticate the Kubernetes and Helm providers with an `exec` block calling `aws eks get-token`, never `data "aws_eks_cluster_auth"`. | A data source is read during plan. On the first apply there is no cluster to read, and the plan fails before anything is created. `exec` runs when the provider connects, which is after the cluster exists. |
| Use `helm_release` and typed `kubernetes_*` resources only, never `kubernetes_manifest`. | `kubernetes_manifest` fetches the API server's schema at plan time, so it cannot be planned against a cluster that does not exist yet. |
| Custom resources live in a chart, not in Terraform. | `SecretStore` and `ExternalSecret` are External Secrets Operator CRDs, and the `roko-api` chart already templates them. |

## What the module does not own

The deployment's own root supplies the provider configuration, the credentials
and the backend block, and owns its `.terraform.lock.hcl` and its state. No
module here contains a backend block, a provider configuration, a credential, a
lock file, a state file or a plan file.

Copy these provider blocks into that root. The `exec` authentication is what lets
the first apply plan against a cluster that does not exist yet.

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.roko.cluster_endpoint
  cluster_ca_certificate = base64decode(module.roko.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.roko.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.roko.cluster_endpoint
    cluster_ca_certificate = base64decode(module.roko.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.roko.cluster_name]
    }
  }
}
```

## Secrets

Terraform generates every secret the deployment needs and writes it to the cloud
secret store. The module takes no secret as an input, so there is no value for a
deployment to paste in and none for this public repository to leak.

| Secret | Where it comes from |
| --- | --- |
| Postgres master credential | `random_password`, written to Secrets Manager (AWS) or, as a whole `postgres://` URL, to Key Vault (Azure). |
| Credential encryption key (`SECRET_ENCRYPTION_KEY`) | `random_bytes`, 32 bytes, written base64 in `{"SECRET_ENCRYPTION_KEY": "..."}`. |

External Secrets Operator projects both into the namespace. The secret, its grant
and the chart values that name it are created by one apply, so a deployment
cannot be half-configured.

## DNS and TLS

Roko owns DNS for every deployment and runs it in Cloudflare. The module creates
no hosted zone, no record and no certificate request, and it never holds a
Cloudflare or registrar credential.

1. **Terraform generates the origin certificate.** Cloudflare presents the
   certificate a browser checks, so the origin's certificate only has to exist.
   `tls_self_signed_cert` signs one for `ingress_host` during the apply, valid ten
   years with no early renewal so it is stable across applies. On AWS it is
   imported into ACM and its ARN becomes the ALB's `certificate-arn`. On Azure it
   is written straight into the `kubernetes.io/tls` Secret `ingress-nginx` reads.
2. **Terraform restricts the load balancer to Cloudflare.** The ranges are read
   from `https://api.cloudflare.com/client/v4/ips` during the apply, so this needs
   no Cloudflare credential and nothing is written down here. The origin then
   cannot be reached around Cloudflare, which is what makes the unvalidated
   Cloudflare-to-origin hop acceptable.
3. **Ops points the record at the output.** Create a proxied `CNAME` in Cloudflare
   from `hostname` to `ingress_hostname` (an `A` on Azure, where the address is an
   IP). One zone-wide setting is done once for `rokolabs.ai`: SSL/TLS mode `Full`.

Three consequences worth stating.

- The allowlist is only as fresh as the last apply. Compare the
  `origin_allowed_cidrs` output against what Cloudflare publishes now; a scheduled
  plan is the cheap way to notice drift.
- A locked-down origin cannot be reached directly for debugging. Add your own
  address to `extra_origin_cidrs` and apply.
- A deployment that will not sit behind Roko's Cloudflare sets `tls_mode` to
  `provided` and supplies its own certificate.
