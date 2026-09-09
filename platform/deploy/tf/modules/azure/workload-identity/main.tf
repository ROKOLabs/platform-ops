# Entra Workload Identity — the Azure analog of the EKS Pod Identity
# associations on AWS. Each k8s ServiceAccount is federated to a user-assigned
# managed identity: a federated credential tells Entra to trust tokens the AKS
# OIDC issuer mints for `system:serviceaccount:<ns>:<sa>`, and a role assignment
# scopes what that identity can do. No keys anywhere; DefaultAzureCredential
# resolves the token in-pod.
#
# Two identities serve three ServiceAccounts:
#   - api              → Storage Blob Data Contributor on the storage account
#                        (used by roko-api and the agent Jobs)
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

# Commented out: the Terraform principal lacks Microsoft.Authorization/roleAssignments/write
# (needs Owner or Contributor + User Access Administrator). Granted manually via
# `az role assignment create` instead — see deploy/plcp/tf/README.md.
# resource "azurerm_role_assignment" "api_blob" {
#   scope                = var.storage_account_id
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = azurerm_user_assigned_identity.api.principal_id
# }

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
