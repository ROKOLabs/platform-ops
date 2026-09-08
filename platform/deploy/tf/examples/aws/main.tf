# A complete AWS deployment root. Copy this file, replace the values marked
# CHANGE ME, and apply. Nothing else has to be written.
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
    bucket       = "acme-prod-tfstate" # CHANGE ME
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
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
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/aws?ref=0.0.13"

  name         = "acme-prod" # CHANGE ME
  region       = "us-east-1" # CHANGE ME, together with the provider above
  azs          = ["us-east-1a", "us-east-1b"]
  ingress_host = "acme.rokolabs.ai" # CHANGE ME

  # A /22 per zone for pods and a /24 per zone for load balancers. Widen it only
  # if this cluster will run much more than the platform. It cannot be changed
  # after the VPC is created.
  vpc_cidr = "10.0.0.0/20"

  # Who may reach the Kubernetes API server. Terraform reaches it too, so the
  # address running this has to be in the list.
  api_allowed_cidrs = ["203.0.113.0/24"] # CHANGE ME

  # A NAT gateway per zone and a standby database in a second zone. Off is
  # cheaper and does not survive losing a zone.
  high_availability = false

  # Who else gets cluster admin. The identity running Terraform is granted it
  # automatically, so this is for the people who need kubectl. Use the FULL
  # pathful ARN: EKS rejects a path-stripped SSO role ARN.
  admin_principal_arns = [
    "arn:aws:iam::111122223333:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_abc123", # CHANGE ME
  ]

  monthly_budget_usd   = 1000
  budget_notify_emails = ["ops@acme.example"] # CHANGE ME
}

# The two values Ops needs to create the DNS record, and nothing else.
output "hostname" { value = module.roko.hostname }
output "ingress_hostname" { value = module.roko.ingress_hostname }
