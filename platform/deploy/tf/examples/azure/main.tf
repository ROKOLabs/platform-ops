# A complete Azure deployment root. Copy this file, replace the values marked
# CHANGE ME, and apply. Nothing else has to be written.
#
# The provider blocks stay here rather than inside the module because a module
# that carries its own provider configuration is a legacy module: Terraform then
# refuses `count`, `for_each` and `depends_on` on it, and removing it leaves
# resources nothing can manage. So they are given here, complete, to copy.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi      = { source = "Azure/azapi", version = "~> 2.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
  }

  # The storage account comes from the one-off bootstrap in the setup guide.
  backend "azurerm" {
    resource_group_name  = "acme-prod-tfstate-rg" # CHANGE ME
    storage_account_name = "acmeprodtfstate"      # CHANGE ME
    container_name       = "tfstate"
    key                  = "platform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000" # CHANGE ME
}

# AKS hands out an admin kubeconfig, so these read the cluster's own credentials
# rather than shelling out. Both providers depend on the module's outputs, so
# every resource they own is applied after the cluster exists.
provider "kubernetes" {
  host                   = module.roko.cluster_endpoint
  cluster_ca_certificate = base64decode(module.roko.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = module.roko.cluster_endpoint
    cluster_ca_certificate = base64decode(module.roko.cluster_ca_certificate)
  }
}

module "roko" {
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/azure?ref=0.0.13"

  name         = "acme-prod" # CHANGE ME
  location     = "southcentralus"
  ingress_host = "acme.rokolabs.ai" # CHANGE ME

  # A /21 for AKS nodes and pods and a /24 for Postgres. Cannot be changed after
  # the VNet is created.
  vnet_cidr = "10.0.0.0/20"

  # Who may reach the Kubernetes API server. Terraform reaches it too, so the
  # address running this has to be in the list.
  api_allowed_cidrs = ["203.0.113.0/24"] # CHANGE ME

  # Azure makes these four globally unique, so the module cannot derive them.
  storage_account_name = "acmeproduploads" # CHANGE ME
  acr_name             = "acmeprodacr"     # CHANGE ME
  key_vault_name       = "acme-prod-kv"    # CHANGE ME
  postgres_server_name = "acme-prod-pg"    # CHANGE ME

  foundry = {
    account_name = "acme-prod-foundry" # CHANGE ME
    project_name = "acme-prod"         # CHANGE ME
    location     = "eastus2"
  }
}

# The two values Ops needs to create the DNS record, and the two a person pastes
# into Settings, Models.
output "hostname" { value = module.roko.hostname }
output "ingress_hostname" { value = module.roko.ingress_hostname }
output "foundry_openai_endpoint" { value = module.roko.foundry_openai_endpoint }
output "foundry_gpt_deployment_name" { value = module.roko.foundry_gpt_deployment_name }
