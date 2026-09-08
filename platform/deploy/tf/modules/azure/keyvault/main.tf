# Key Vault — the Azure analog of Secrets Manager. RBAC authorization (not access
# policies) so grants are plain role assignments, matching the IAM model used
# everywhere else. Secrets Manager had no Terraform module; this one is new.
#
# The vault holds the database connection written by the Postgres module and the
# encryption key used for runtime credentials. The encryption key is seeded out
# of band. This module grants the deployer write access. Roko CR-26 removed the
# web-auth secret because first-party auth keeps sessions in the API's Postgres.
resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = false
}

# Lets a human (or the CI principal) seed the out-of-band secrets with
# `az keyvault secret set`.
#
# Commented out: the Terraform principal lacks Microsoft.Authorization/roleAssignments/write
# (needs Owner or Contributor + User Access Administrator). Granted manually via
# `az role assignment create` instead — see deploy/plcp/tf/README.md.
# resource "azurerm_role_assignment" "secrets_officer" {
#   for_each             = toset(var.admin_object_ids)
#   scope                = azurerm_key_vault.this.id
#   role_definition_name = "Key Vault Secrets Officer"
#   principal_id         = each.value
# }
