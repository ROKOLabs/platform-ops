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

  # A deleted vault keeps its name reserved for the whole retention window, so a
  # destroy-and-recreate of the same deployment fails until somebody purges it by
  # hand. Seven days is the minimum Azure allows and the shortest that trap runs.
  soft_delete_retention_days = var.soft_delete_retention_days
}

# The vault authorizes by RBAC, so creating it grants nobody anything, not even
# its creator. Terraform writes the database URL and the encryption key into it
# during the same apply, so without this it creates a vault it is then forbidden
# to use and the apply fails 403. This used to be granted out of band with
# `az role assignment create`, which is what made the first apply a two-step.
#
# It needs Microsoft.Authorization/roleAssignments/write, so the principal
# applying this module has to be Owner, or Contributor plus User Access
# Administrator. The setup guide says so.
resource "azurerm_role_assignment" "secrets_officer" {
  for_each = toset(var.admin_object_ids)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

# Azure RBAC is eventually consistent: a data-plane call made immediately after
# the assignment is created is still refused. Without this the first apply fails
# 403 on the first secret and succeeds on a retry, which is the least debuggable
# kind of failure.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.secrets_officer]
  create_duration = "60s"
}
