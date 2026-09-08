# A complete Azure deployment root. Copy this file, set the values in
# terraform.tfvars, and apply. Nothing else has to be written.
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
    resource_group_name  = "CHANGE-ME-tfstate-rg"
    storage_account_name = "CHANGEMEtfstate"
    container_name       = "tfstate"
    key                  = "platform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
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
  source = "git::https://github.com/ROKOLabs/platform-ops.git//platform/deploy/tf/modules/azure?ref=0.0.12"

  name         = var.name
  location     = var.location
  ingress_host = var.ingress_host

  storage_account_name = var.storage_account_name
  acr_name             = var.acr_name
  key_vault_name       = var.key_vault_name
  postgres_server_name = var.postgres_server_name

  foundry = var.foundry
}

variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "name" {
  description = "Name prefix for every resource, and the resource group's name."
  type        = string
}

variable "location" {
  type    = string
  default = "southcentralus"
}

variable "ingress_host" {
  description = "Public hostname this deployment serves."
  type        = string
}

# Azure makes these four globally unique, so they cannot be derived from `name`.
variable "storage_account_name" { type = string }
variable "acr_name" { type = string }
variable "key_vault_name" { type = string }
variable "postgres_server_name" { type = string }

variable "foundry" {
  description = "Foundry account, project and model deployments."
  type = object({
    account_name = string
    project_name = string
    location     = optional(string)
  })
}

# The two values Ops needs to create the DNS record, and the two a person pastes
# into Settings, Models.
output "hostname" { value = module.roko.hostname }
output "ingress_hostname" { value = module.roko.ingress_hostname }
output "foundry_openai_endpoint" { value = module.roko.foundry_openai_endpoint }
output "foundry_gpt_deployment_name" { value = module.roko.foundry_gpt_deployment_name }
