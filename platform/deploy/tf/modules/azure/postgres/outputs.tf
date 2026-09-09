output "server_name" { value = azurerm_postgresql_flexible_server.this.name }
output "fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "database_name" { value = azurerm_postgresql_flexible_server_database.platform.name }
output "database_url_secret_name" { value = azurerm_key_vault_secret.database_url.name }
