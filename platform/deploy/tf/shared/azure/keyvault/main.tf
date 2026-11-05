# Key Vault — the Azure analog of Secrets Manager. RBAC authorization by default,
# so grants are plain role assignments, matching the IAM model used everywhere
# else. Secrets Manager had no Terraform module; this one is new.
#
# `authorization = "access_policy"` is for a principal that holds Contributor and
# nothing more. Granting a role, and switching a vault between the two models,
# both need Microsoft.Authorization/roleAssignments/write; writing an access
# policy is a control-plane write on the vault itself, which Contributor covers.
# The trade: access policies are per-vault, do not inherit, and do not appear in
# Azure access reviews.
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

  rbac_authorization_enabled = var.authorization == "rbac"
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
  for_each = var.authorization == "rbac" ? toset(var.admin_object_ids) : toset([])

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

# Azure RBAC is eventually consistent: a data-plane call made immediately after
# the assignment is created is still refused. Without this the first apply fails
# 403 on the first secret and succeeds on a retry, which is the least debuggable
# kind of failure.
moved {
  from = time_sleep.rbac_propagation
  to   = time_sleep.rbac_propagation[0]
}

resource "time_sleep" "rbac_propagation" {
  count = var.authorization == "rbac" ? 1 : 0

  depends_on      = [azurerm_role_assignment.secrets_officer]
  create_duration = "60s"
}

# The access-policy equivalent of the Secrets Officer grant. Purge is included
# because the provider's default features block purges a soft-deleted secret on
# destroy; without it, destroying a secret fails. Access policies take effect at
# once, so this path has no propagation pause.
resource "azurerm_key_vault_access_policy" "admins" {
  for_each = var.authorization == "access_policy" ? toset(var.admin_object_ids) : toset([])

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Purge"]
}
