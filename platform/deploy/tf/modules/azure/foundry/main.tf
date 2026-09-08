# Microsoft Foundry account. Local authentication stays enabled because the
# platform's first Azure deployment stores and uses an account API key.
resource "azapi_resource" "account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-10-01-preview"
  name      = var.account_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      customSubDomainName    = var.account_name
      allowProjectManagement = true
      publicNetworkAccess    = "Enabled"
      disableLocalAuth       = false
    }
  }
}

# The project provides the Foundry portal and playground boundary for this
# deployment. Its managed identity is not used by the platform agent pods.
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview"
  name      = var.project_name
  parent_id = azapi_resource.account.id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }
}

# modelProviderData accepts the Anthropic Marketplace terms for this legal
# organization. AzAPI is required because azurerm does not expose this field.
# Model version 2 selects the Hosted on Azure variant of Claude Sonnet 5.
moved {
  from = azapi_resource.claude_sonnet_5
  to   = azapi_resource.claude_sonnet_5[0]
}

resource "azapi_resource" "claude_sonnet_5" {
  count = var.deployment_enabled ? 1 : 0

  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name                      = var.deployment_name
  parent_id                 = azapi_resource.account.id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.deployment_sku
      capacity = var.deployment_capacity
    }
    properties = {
      model = {
        format  = "Anthropic"
        name    = "claude-sonnet-5"
        version = "2"
      }
      modelProviderData = {
        organizationName = var.organization_name
        countryCode      = var.country_code
        industry         = var.industry
      }
      versionUpgradeOption = "OnceNewDefaultVersionAvailable"
      raiPolicyName        = "Microsoft.DefaultV2"
    }
  }

  depends_on = [azapi_resource.project]
}

# The base model the platform actually uses on Azure. `azure-openai` is the only
# provider kind an AKS deployment can authenticate, and its catalog holds one
# model, `gpt-5.4-mini`, so this deployment is what an agent run resolves.
#
# No modelProviderData block: those fields accept the Anthropic Marketplace
# terms and an OpenAI-format deployment neither needs nor accepts them.
#
# azurerm, where the account and project above are azapi. azapi's generic
# resource cannot import a Microsoft.CognitiveServices/accounts/deployments at
# all: its ImportState returns no state, identically from an import block and
# from `terraform import`, so a deployment that already exists in Azure can
# never be adopted and every plan tries to create it again. azurerm carries a
# typed resource for this one shape, with conventional import. The account and
# the project have no azurerm equivalent, so they stay on azapi.
resource "azurerm_cognitive_deployment" "gpt" {
  count = var.gpt_deployment_enabled ? 1 : 0

  name                 = var.gpt_deployment_name
  cognitive_account_id = azapi_resource.account.id

  # version is optional; null lets Azure serve the model's current default.
  model {
    format  = "OpenAI"
    name    = "gpt-5.4-mini"
    version = var.gpt_model_version
  }

  sku {
    name     = var.gpt_deployment_sku
    capacity = var.gpt_deployment_capacity
  }

  version_upgrade_option = "OnceNewDefaultVersionAvailable"
  rai_policy_name        = "Microsoft.DefaultV2"

  depends_on = [azapi_resource.project]
}
