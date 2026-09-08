# A complete AWS deployment root. Copy this file, set the values in
# terraform.tfvars, and apply. Nothing else has to be written.
#
# The provider blocks stay here rather than inside the module because a module
# that carries its own provider configuration is a legacy module: Terraform then
# refuses `count`, `for_each` and `depends_on` on it, and removing it leaves
# resources nothing can manage. So they are given here, complete, to copy.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
  }

  # The bucket comes from the one-off bootstrap in the setup guide.
  backend "s3" {
    bucket       = "CHANGE-ME-tfstate"
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}

# Authenticated with an exec block, never `data "aws_eks_cluster_auth"`. A data
# source is read during plan, and on the first apply there is no cluster to read,
# so the plan fails before anything is created. exec runs when the provider
# connects, which is after the cluster exists. This is what makes one apply work.
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

module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.12"

  name         = var.name
  region       = var.region
  azs          = var.azs
  ingress_host = var.ingress_host

  admin_role_arns = var.admin_role_arns

  monthly_budget_usd   = var.monthly_budget_usd
  budget_notify_emails = var.budget_notify_emails
}

variable "name" {
  description = "Name prefix for every resource, for example acme-prod."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "ingress_host" {
  description = "Public hostname this deployment serves."
  type        = string
}

variable "admin_role_arns" {
  description = "Roles granted cluster admin. Use the FULL pathful ARN."
  type        = list(string)
  default     = []
}

variable "monthly_budget_usd" {
  type    = number
  default = null
}

variable "budget_notify_emails" {
  type    = list(string)
  default = []
}

# The two values Ops needs to create the DNS record, and nothing else.
output "hostname" { value = module.roko.hostname }
output "ingress_hostname" { value = module.roko.ingress_hostname }
