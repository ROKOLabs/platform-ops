# Deploying the Roko platform

One `terraform apply` produces a working deployment: network, Kubernetes
cluster, Postgres, object storage, container registries, budget, every secret,
and the Helm release that runs the platform. There is no second apply, no
`-target`, and no `helm` command.

Pick the cloud you are deploying to and follow the steps in order. Everything
you can set is in the appendices.

## Before you start

| | |
| --- | --- |
| Terraform | 1.11 or newer. |
| AWS | An account, and the `aws` CLI signed in with permission to create VPCs, EKS clusters, RDS instances, S3 buckets, IAM roles and Secrets Manager secrets. |
| Azure | A subscription, and the `az` CLI signed in with Owner, or Contributor plus User Access Administrator. The module assigns a role, which Contributor alone cannot do. |
| DNS | A hostname for the deployment. Roko owns DNS and runs it in Cloudflare; you will create one record at the end. |

You do not need a certificate, and you do not need to create any secret by hand.
Terraform generates both.

## 1. Create the state backend

One-off, and deliberately outside the deployment: it creates the place the
deployment's state lives, so it cannot live there itself.

**AWS.** Write this in an empty directory and apply it. Its own state stays
local, which is why it is separate.

```hcl
module "tf_backend" {
  source      = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws/tf-backend?ref=0.0.12"
  bucket_name = "acme-prod-tfstate"
}
```

**Azure.** Three CLI commands, no Terraform.

```bash
az group create --name acme-prod-tfstate-rg --location southcentralus
az storage account create --name acmeprodtfstate --resource-group acme-prod-tfstate-rg --sku Standard_LRS
az storage container create --name tfstate --account-name acmeprodtfstate
```

## 2. Copy the deployment root

Copy one directory into your own repository. It is a complete root: the
`terraform` block, the provider configuration, the module call, and the outputs
Ops needs. Nothing else has to be written.

| Cloud | Copy |
| --- | --- |
| AWS | [`examples/aws`](examples/aws) |
| Azure | [`examples/azure`](examples/azure) |

The provider blocks are in that file rather than inside the module on purpose. A
module that carries its own provider configuration is a legacy module in
Terraform's terms: callers may then not use `count`, `for_each` or `depends_on`
on it, and removing it leaves resources nothing can manage. Copying twenty lines
once is the cheaper trade.

Two details in the AWS file matter and should not be edited. The Kubernetes and
Helm providers authenticate with an `exec` block rather than
`data "aws_eks_cluster_auth"`, because a data source is read during plan and on
the first apply there is no cluster to read. And no configuration anywhere uses
`kubernetes_manifest`, which fetches the API server's schema at plan time.
Together those are what make a single apply possible.

## 3. Fill in the values

Rename `terraform.tfvars.example` to `terraform.tfvars` and set it. Then set the
backend bucket or storage account you created in step 1, at the top of
`main.tf`.

**AWS** needs four values: `name`, `region`, `azs` and `ingress_host`. Add
`admin_role_arns` unless you intend nobody to have cluster admin.

**Azure** needs those plus four globally unique names Azure will not let the
module derive: `storage_account_name`, `acr_name`, `key_vault_name` and
`postgres_server_name`, and a `foundry` account and project name.

Everything else has a default. Appendix A and Appendix C list all of it.

## 4. Apply

```bash
terraform init
terraform apply
```

Expect roughly 25 minutes, most of it the cluster and the database. The apply is
ordered by dependencies rather than by a person: the network, then the cluster,
then External Secrets Operator, then the platform. Run it again with no input
changes and the plan is empty.

While it runs, this is what Terraform generates so that nobody has to:

| Secret | Where it goes |
| --- | --- |
| Postgres master credential | Secrets Manager on AWS, or the whole `postgres://` URL into Key Vault on Azure. |
| `SECRET_ENCRYPTION_KEY` | The same store, as `{"SECRET_ENCRYPTION_KEY": "..."}`. Without it, saving a model-provider or code-host credential answers 409. |
| Origin certificate | Self-signed for your hostname, ten-year validity. Imported into ACM on AWS; written into the TLS Secret on Azure. |

External Secrets Operator projects the first two into the namespace. The module
takes no secret as an input, so there is nothing to paste in and nothing to
leak.

## 5. Point DNS at it

```bash
terraform output hostname
terraform output ingress_hostname
```

Create one **proxied** record in Cloudflare from the first to the second: a
`CNAME` on AWS, an `A` on Azure, where the address is an IP.

One setting is done once for the whole zone, not per deployment: SSL/TLS mode
**Full**.

That is the whole TLS story. Cloudflare presents the certificate a browser
checks, so the origin's certificate only has to exist, and the module already
made one. Terraform also read Cloudflare's published address ranges during the
apply and restricted the load balancer to them, so the origin cannot be reached
around Cloudflare. That restriction is what makes an unvalidated
Cloudflare-to-origin hop acceptable, so leave it on.

## 6. Verify

```bash
curl -sSf "https://$(terraform output -raw hostname)/api/health"
```

To look inside the cluster:

```bash
# AWS
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)"
# Azure
az aks get-credentials --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw cluster_name)"

kubectl get pods -n service
```

On Azure, finish by pasting `foundry_openai_endpoint` and
`foundry_gpt_deployment_name` into Settings, Models, beside an account API key.
Bedrock is unreachable from AKS, so `azure-openai` is the provider kind that
deployment serves.

## Day two

**Upgrade to a new release.** Change the `?ref=` in your `source` and apply. One
version resolves the infrastructure, the chart and the images together, so there
is no second number to reconcile.

**Override something the module does not expose.** Pass `chart_values`. It is
handed to Helm as a second values document, so the merge is deep and overriding
one nested key leaves its siblings alone.

```hcl
chart_values = {
  api = { nodeEnv = "development" }
}
```

**Reach a locked-down origin directly.** Add your address to
`extra_origin_cidrs` and apply. There is no console button for this, by design.

**Watch for allowlist drift.** The ranges are only as fresh as the last apply.
Cloudflare changes them rarely and announces it, but a deployment nobody has
applied since a change refuses traffic from the new range, and it presents as a
partial outage that looks like a Cloudflare fault. The `origin_allowed_cidrs`
output records what this apply allowed; a scheduled plan is the cheap way to
notice.

**Serve a certificate somebody else issued.** Set `tls_mode = "provided"`. On
AWS, pass the ACM ARN as `tls_certificate_arn`. On Azure, the module creates the
TLS Secret empty, stops managing its value, and `tls_secret_id` names it. This is
the only path for a deployment that will not sit behind Roko's Cloudflare, and
such a deployment also sets `restrict_origin_to_cloudflare = false`.

## Common variations

### AWS

#### Production sizing

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = "acme-prod"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b", "us-east-1c"]
  ingress_host = "acme.rokolabs.ai"

  # One NAT gateway per zone, so losing a zone does not take egress with it.
  single_nat_gateway = false

  # Reach the API server from the office range only.
  api_allowed_cidrs = ["203.0.113.0/24"]

  db_instance_class        = "db.m7g.large"
  db_allocated_storage     = 200
  db_multi_az              = true
  db_backup_retention_days = 30

  monthly_budget_usd   = 5000
  budget_notify_emails = ["ops@acme.example"]
}
```

#### A deployment that will not sit behind Cloudflare

`provided` is the only path that keeps a certificate somebody else issued. Turning the Cloudflare restriction off without it would leave an origin whose certificate proves nothing reachable by anyone.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = "acme-prod"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b"]
  ingress_host = "acme.example.com"

  tls_mode            = "provided"
  tls_certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/d14ffd57-9736-42f6-a306-bb69d2f686c1"

  restrict_origin_to_cloudflare = false
}
```

#### Adopting resources that already exist

A deployment migrating off hand-written Terraform states the names it already has, so no bucket is recreated and no repository is orphaned. Import the existing resources into this module's addresses first, then apply.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = "rokolabs-dev"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b"]
  vpc_cidr     = "10.180.0.0/16"
  ingress_host = "platform.dev.rokolabs.ai"

  uploads_bucket_name     = "roko-platform-uploads-dev"
  checkpoints_bucket_name = "roko-platform-agent-checkpoints-dev"
  ecr_repository_names    = { api = "roko-api", web = "roko-web", agent = "roko-agent" }

  # The certificate and the record it fronts already exist; move TLS after the
  # state is settled, not during the same apply.
  tls_mode                      = "provided"
  tls_certificate_arn           = "arn:aws:acm:us-east-1:962565294103:certificate/d14ffd57-9736-42f6-a306-bb69d2f686c1"
  restrict_origin_to_cloudflare = false
}
```

#### A lane that builds its own images

The only supported override of the version constant. It changes the images, never the chart.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = "rokolabs-dev"
  region       = "us-east-1"
  azs          = ["us-east-1a", "us-east-1b"]
  ingress_host = "platform.dev.rokolabs.ai"

  image_registry = "962565294103.dkr.ecr.us-east-1.amazonaws.com"
  image_names    = { api = "roko-api", web = "roko-web", agent = "roko-agent" }
  image_tag      = var.sha_tag

  # Anything the module does not expose. Merged deeply over the computed values,
  # so this leaves the rest of `api` alone.
  chart_values = {
    api = {
      nodeEnv = "development"
      otel    = { endpoint = "http://alloy.observability.svc.cluster.local:4318" }
    }
  }
}
```

### Azure

#### Sizing the agent pool

Memory limits each node to one agent, so the node ceiling and the agent concurrency cap move together.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/azure?ref=0.0.12"

  name         = "acme-prod"
  location     = "southcentralus"
  ingress_host = "acme.rokolabs.ai"

  storage_account_name = "acmeproduploads"
  acr_name             = "acmeprodacr"
  key_vault_name       = "acme-prod-kv"
  postgres_server_name = "acme-prod-pg"

  agent_node_vm_size   = "Standard_D8s_v5"
  agent_node_min_count = 2
  agent_node_max_count = 6

  api_allowed_cidrs = ["203.0.113.0/24"]

  foundry = {
    account_name            = "acme-prod-foundry"
    project_name            = "acme-prod"
    location                = "eastus2"
    gpt_deployment_capacity = 48000
  }
}
```

#### A certificate the deployment supplies

`provided` creates the TLS Secret empty and stops managing its value, so a pipeline or a person can drop a real certificate into the name `tls_secret_id` reports.

```hcl
module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/azure?ref=0.0.12"

  name         = "acme-prod"
  location     = "southcentralus"
  ingress_host = "acme.example.com"

  storage_account_name = "acmeproduploads"
  acr_name             = "acmeprodacr"
  key_vault_name       = "acme-prod-kv"
  postgres_server_name = "acme-prod-pg"

  tls_mode                      = "provided"
  restrict_origin_to_cloudflare = false

  foundry = {
    account_name = "acme-prod-foundry"
    project_name = "acme-prod"
  }
}
```

## Appendix A: `modules/aws` inputs

### Required

| Input | Type | Purpose |
| --- | --- | --- |
| `name` | string | Name prefix for every resource, for example `acme-prod`. Also the default stem of every bucket, repository and IAM role name. |
| `region` | string | AWS region. Must match the region the calling provider is configured for. |
| `azs` | list(string) | Availability zones. One private `/20` and one public `/24` subnet per zone. |
| `ingress_host` | string | Public hostname the platform serves, for example `acme.rokolabs.ai`. Names the Ingress host rule and the origin certificate. |

### Network and cluster

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC range. Cannot be changed after creation. |
| `single_nat_gateway` | bool | `true` | `true` shares one NAT gateway across every zone. `false` creates one per zone. |
| `kubernetes_version` | string | `1.34` | EKS version. |
| `api_allowed_cidrs` | list(string) | `["0.0.0.0/0"]` | Who may reach the EKS public API endpoint. |
| `admin_role_arns` | list(string) | `[]` | Roles granted cluster admin. Use the FULL pathful ARN: EKS rejects path-stripped SSO role ARNs. |
| `viewer_role_arns` | list(string) | `[]` | Roles granted cluster-wide read access. Same pathful-ARN rule. |

### TLS and origin access

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `tls_mode` | string | `self_signed` | `self_signed` generates the origin certificate during the apply and imports it into ACM. `provided` serves `tls_certificate_arn` instead and generates nothing. |
| `tls_certificate_arn` | string | `""` | ACM certificate the load balancer serves. Required when `tls_mode` is `provided`, ignored otherwise. |
| `restrict_origin_to_cloudflare` | bool | `true` | Restricts the load balancer to Cloudflare's published ranges, read at apply time. Turn it off only for a deployment that does not sit behind Cloudflare. |
| `extra_origin_cidrs` | list(string) | `[]` | Additional IPv4 CIDRs allowed to reach the load balancer, for reaching a locked-down origin directly. |

### Database

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `db_instance_class` | string | `db.t4g.micro` | Postgres instance class. |
| `db_allocated_storage` | number | `20` | Storage in GiB. |
| `db_multi_az` | bool | `false` | Runs a standby in a second zone. |
| `db_backup_retention_days` | number | `7` | Automated backup retention. |
| `db_deletion_protection` | bool | `true` | Refuses to destroy the instance until turned off and applied. |

### Images and chart

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `image_registry` | string | `docker.io/rokoplatform` | Registry the chart pulls from. |
| `image_names` | object | `{}` | Repository name per image: `api`, `web`, `agent`. Defaults are Docker Hub's. |
| `image_tag` | string | `""` | Empty means the module's own version. Set only by a lane that builds its own images. |
| `chart_values` | any | `{}` | Merged over the computed chart values. Passed to Helm as a second values document, so the merge is deep. |
| `external_secrets_chart_version` | string | `2.8.0` | external-secrets chart version. |

### Names

Every name defaults to one derived from `name`, which is what a new deployment wants. They are overridable because a bucket name and a repository name are both force-new and a bucket holding objects cannot be renamed, so a deployment adopting resources that already exist can state their names rather than move their contents.

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `uploads_bucket_name` | string | `""` | Uploads bucket. Empty means `<name>-uploads`. |
| `checkpoints_bucket_name` | string | `""` | Agent checkpoints bucket. Empty means `<name>-agent-checkpoints`. |
| `ecr_repository_names` | object | `{}` | Repository per image: `api`, `web`, `agent`. Each unset key means `<name>-<key>`. |

### Artifacts and agents

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `artifact_cors_origins` | list(string) | `[]` | Browser origins allowed to PUT/GET the uploads bucket through presigned URLs. Empty means `https://<ingress_host>` alone. |
| `agent_bedrock_model_arns` | list(string) | any model in the account | Bedrock model and inference-profile ARNs the agent role may invoke. |
| `agent_checkpoint_prefix` | string | `runs` | Key prefix run checkpoints are written under. Both IAM grants are scoped to it. |
| `agent_checkpoint_expiration_days` | number | `30` | Backstop expiry for checkpoint objects the backend's own cleanup missed. |

### Budget and tagging

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `monthly_budget_usd` | number | `null` | Monthly cost budget. Null creates no budget. |
| `budget_notify_emails` | list(string) | `[]` | Addresses the budget alerts. Required when `monthly_budget_usd` is set. |
| `tags` | map(string) | `{}` | Added to every taggable resource, on top of `Project` and `ManagedBy`. |

## Appendix B: `modules/aws` outputs

| Output | Purpose |
| --- | --- |
| `cluster_name` | For `aws eks update-kubeconfig` and for CI. |
| `cluster_endpoint`, `cluster_ca_certificate` | Configure the deployment's own Kubernetes and Helm providers. |
| `db_host` | Postgres endpoint. |
| `uploads_bucket`, `checkpoints_bucket` | Object storage the Artifacts, Prototypes and agent features use. |
| `hostname` | The name this deployment serves, echoed back, so Ops knows the record to create. |
| `ingress_hostname` | The load balancer address that record points at. |
| `tls_secret_id` | The certificate the load balancer serves. Null unless `tls_mode` is `provided`. |
| `origin_allowed_cidrs` | The Cloudflare ranges this apply allowed, as `{ipv4, ipv6}`, so drift is visible in a plan. |
| `platform_version` | The release this module deploys. |
| `api_ecr_repository_url`, `web_ecr_repository_url`, `agent_ecr_repository_url` | Registries a lane that builds its own images pushes to. |

## Appendix C: `modules/azure` inputs

The same shape with Azure's own names. Four names are required rather than derived, because Azure makes them globally unique.

### Required

| Input | Type | Purpose |
| --- | --- | --- |
| `name` | string | Name prefix for every resource, and the resource group's name. |
| `location` | string | Azure region. |
| `ingress_host` | string | Public hostname the platform serves. |
| `storage_account_name` | string | Uploads storage account. Globally unique, 3-24 lowercase alphanumerics. |
| `acr_name` | string | Container registry. Globally unique, 5-50 alphanumerics. |
| `key_vault_name` | string | Key Vault. Globally unique, 3-24 alphanumerics and hyphens. |
| `postgres_server_name` | string | PostgreSQL Flexible Server. Globally unique, lowercase. |
| `foundry` | object | Foundry account, project and model deployments. See the table below. |

### Network and cluster

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `vnet_cidr` | string | `10.0.0.0/16` | VNet address space. Cannot be changed after creation. |
| `kubernetes_version` | string | `1.36` | AKS version. |
| `api_allowed_cidrs` | list(string) | `[]` | Who may reach the AKS public API server. Empty means open. |
| `agent_node_vm_size` | string | `Standard_D4s_v5` | VM size for the autoscaling agent pool. A D4s_v5 has room for one three-CPU agent Job plus the AKS DaemonSets. |
| `agent_node_min_count` | number | `1` | Warm agent nodes. |
| `agent_node_max_count` | number | `3` | Autoscale ceiling. Memory limits each node to one agent, so this is also the agent concurrency cap. |

### TLS and origin access

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `tls_mode` | string | `self_signed` | `self_signed` writes the generated certificate straight into the TLS Secret `ingress-nginx` reads. `provided` creates that Secret empty, ignores its value afterwards, and serves whatever is dropped in. |
| `restrict_origin_to_cloudflare` | bool | `true` | Restricts the controller's `loadBalancerSourceRanges` to Cloudflare's published ranges, read at apply time. |
| `extra_origin_cidrs` | list(string) | `[]` | Additional CIDRs allowed to reach the load balancer. |
| `ingress_nginx_chart_version` | string | `4.11.3` | AKS ships no load balancer controller, so the module installs the one the Ingress names. |

### Images, chart and containers

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `image_registry` | string | `docker.io/rokoplatform` | Registry the chart pulls from. |
| `image_names` | object | `{}` | Repository name per image: `api`, `web`, `agent`. |
| `image_tag` | string | `""` | Empty means the module's own version. |
| `chart_values` | any | `{}` | Merged deeply over the computed chart values. |
| `uploads_container_name` | string | `uploads` | Blob container shared by artifacts and prototypes. |
| `checkpoints_container_name` | string | `agent-checkpoints` | Private container for agent checkpoint archives. |
| `artifact_cors_origins` | list(string) | `[]` | Origins allowed to PUT/GET blobs through SAS URLs. Empty means `https://<ingress_host>` alone. |
| `external_secrets_chart_version` | string | `2.8.0` | external-secrets chart version. |

### `foundry`

`azure-openai` is the only provider kind an AKS pod can authenticate, so the GPT deployment is what the platform actually serves. The Claude deployment stays off: no provider kind can address it, and Azure Marketplace does not support CSP subscriptions.

| Key | Type | Default | Purpose |
| --- | --- | --- | --- |
| `account_name` | string | required | Foundry account. Globally unique, 2-64 lowercase alphanumerics or hyphens. |
| `project_name` | string | required | Foundry project. |
| `location` | string | the deployment's region | Region for the account and its deployments. |
| `gpt_deployment_enabled` | bool | `true` | Whether to deploy the model the platform reads. |
| `gpt_deployment_name` | string | `gpt-5.4-mini` | Deployment name entered in the model-provider form. |
| `gpt_deployment_sku` | string | `GlobalStandard` | Deployment type. |
| `gpt_deployment_capacity` | number | `24000` | Input-token quota, thousands per minute. |
| `gpt_model_version` | string | `null` | Null lets Azure serve the current default version. |
| `claude_enabled` | bool | `false` | Leave false. Applying it accepts the Anthropic Marketplace terms for the organization below. |
| `claude_deployment_name`, `claude_deployment_sku`, `claude_capacity` | | `claude-sonnet-5`, `GlobalStandard`, `25` | Read only when `claude_enabled` is true. |
| `organization_name`, `country_code`, `industry` | string | `ROKO Labs`, `US`, `technology` | Legal details for those Marketplace terms. |

### Misc

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `extra_secrets_officer_object_ids` | list(string) | `[]` | Principals granted Key Vault Secrets Officer on top of the Terraform principal. |
| `tags` | map(string) | `{}` | Added to every taggable resource. |

## Appendix D: `modules/azure` outputs

The names match `modules/aws` wherever the thing behind them matches, so a caller reads `db_host` and `uploads_bucket` on either cloud.

| Output | Purpose |
| --- | --- |
| `cluster_name` | For `az aks get-credentials` and for CI. |
| `cluster_endpoint`, `cluster_ca_certificate` | Configure the deployment's own Kubernetes and Helm providers. |
| `resource_group_name` | Resource group holding the deployment. |
| `db_host` | Postgres FQDN. The pod reads the whole URL from Key Vault; this is for a person connecting by hand. |
| `uploads_bucket`, `checkpoints_bucket` | The two Blob containers. |
| `hostname` | The name this deployment serves. |
| `ingress_hostname` | The controller's load balancer IP. On Azure the record is an `A`, not a `CNAME`. |
| `tls_secret_id` | The Secret to drop a certificate into. Null unless `tls_mode` is `provided`. |
| `origin_allowed_cidrs` | The Cloudflare ranges this apply allowed. |
| `platform_version` | The release this module deploys. |
| `acr_login_server` | Registry a lane that builds its own images pushes to. |
| `foundry_openai_endpoint`, `foundry_gpt_deployment_name` | The two values a person pastes into Settings, Models, beside an account API key. |
