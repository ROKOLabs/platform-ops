# Entra Workload Identity — the Azure analog of the EKS Pod Identity
# associations on AWS. Each k8s ServiceAccount is federated to a user-assigned
# managed identity: a federated credential tells Entra to trust tokens the AKS
# OIDC issuer mints for `system:serviceaccount:<ns>:<sa>`, and a role assignment
# scopes what that identity can do. No keys anywhere; DefaultAzureCredential
# resolves the token in-pod.
#
# Three identities serve three ServiceAccounts:
#   - api              → Storage Blob Data Contributor on the storage account
#                        and Foundry User on the Foundry account
#                        (used by roko-api and the agent Jobs)
#   - tickets          → Azure DevOps Boards access granted by an organization
#                        administrator (used only by roko-api)
#   - external-secrets → Key Vault Secrets User on the vault

# --- roko-api: blob read/write for artifacts + prototypes --------------------
resource "azurerm_user_assigned_identity" "api" {
  name                = "${var.name}-api"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "api" {
  name                = "${var.name}-api"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.api.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.service_namespace}:${var.api_service_account}"
}

resource "azurerm_federated_identity_credential" "agent" {
  name                = "${var.name}-agent"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.api.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.agents_namespace}:${var.agent_service_account}"
}

# Read deployed models and invoke them through the Foundry data plane. Use the
# built-in role ID because Microsoft recently renamed Azure AI User to Foundry
# User and recommends IDs while the new name rolls out.
resource "azurerm_role_assignment" "api_foundry_user" {
  scope                            = var.foundry_account_id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azurerm_user_assigned_identity.api.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Commented out: the Terraform principal lacks Microsoft.Authorization/roleAssignments/write
# (needs Owner or Contributor + User Access Administrator). Granted manually via
# `az role assignment create` instead — see deploy/plcp/tf/README.md.
# resource "azurerm_role_assignment" "api_blob" {
#   scope                = var.storage_account_id
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = azurerm_user_assigned_identity.api.principal_id
# }

# --- tickets: Azure DevOps Boards as the platform identity ------------------
#
# Keep this identity separate from the API identity. Agent Jobs can assume the
# API identity, but only roko-api should be able to request an Azure DevOps
# token. Azure DevOps permissions are assigned in the organization, not by an
# Azure role assignment in this module.
resource "azurerm_user_assigned_identity" "tickets" {
  name                = "${var.name}-tickets"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "tickets" {
  name                = "${var.name}-tickets"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.tickets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.service_namespace}:${var.api_service_account}"
}

# --- external-secrets: read secrets from Key Vault ---------------------------
resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.name}-external-secrets"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name                = "${var.name}-external-secrets"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.external_secrets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"
}

# Commented out: the Terraform principal lacks Microsoft.Authorization/roleAssignments/write
# (needs Owner or Contributor + User Access Administrator). Granted manually via
# `az role assignment create` instead — see deploy/plcp/tf/README.md.
# resource "azurerm_role_assignment" "external_secrets_kv" {
#   scope                = var.key_vault_id
#   role_definition_name = "Key Vault Secrets User"
#   principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
# }

# Under `access_policy` the read grant is a control-plane write on the vault,
# which the deploy principal is allowed to make, so nothing is manual on that
# path.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_access_policy" "external_secrets" {
  count = var.key_vault_authorization == "access_policy" ? 1 : 0

  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.external_secrets.principal_id

  secret_permissions = ["Get", "List"]
}
