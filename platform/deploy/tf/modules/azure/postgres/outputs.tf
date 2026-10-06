output "server_name" { value = azurerm_postgresql_flexible_server.this.name }
output "fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "database_name" { value = azurerm_postgresql_flexible_server_database.platform.name }
output "database_url_secret_name" { value = azurerm_key_vault_secret.database_url.name }
output "server_id" { value = azurerm_postgresql_flexible_server.this.id }

# The telemetry collector reads Postgres statistics as the administrator.
output "administrator_login" {
  value     = azurerm_postgresql_flexible_server.this.administrator_login
  sensitive = true
}

output "administrator_password" {
  value     = random_password.admin.result
  sensitive = true
}
