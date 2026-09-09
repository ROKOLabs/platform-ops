output "vault_id" { value = azurerm_key_vault.this.id }
output "vault_uri" { value = azurerm_key_vault.this.vault_uri }
output "vault_name" { value = azurerm_key_vault.this.name }

# A caller writing a secret should depend on this module as a whole, which waits
# for the Secrets Officer grant and the pause that lets it propagate.
output "ready" {
  description = "Resolves once the Secrets Officer grant on this vault is usable."
  value       = time_sleep.rbac_propagation.id
}
