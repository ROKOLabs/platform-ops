output "account_name" { value = azurerm_storage_account.this.name }
output "account_id" { value = azurerm_storage_account.this.id }
output "container_name" { value = azurerm_storage_container.uploads.name }
output "checkpoints_container_name" { value = azurerm_storage_container.checkpoints.name }
