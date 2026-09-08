# PostgreSQL Flexible Server — the Azure analog of RDS. VNet-integrated (private,
# no public endpoint), matching RDS in private subnets. The one real divergence
# from AWS: RDS emits a managed {username,password} secret that rotates and never
# touches state; Azure has no equivalent, so Terraform generates the password and
# writes the full connection string to Key Vault, which ESO maps straight to
# DATABASE_URL. database-options.ts consumes the standard URL + DATABASE_SSL
# unchanged. The password lives in Terraform state (encrypted in the Azure state
# backend) — the accepted cost of Flexible Server having no managed secret.
resource "random_password" "admin" {
  length = 28
  # Alphanumeric only: no URL-reserved characters in the connection string's
  # userinfo, and upper+lower+digit already satisfies Azure's complexity policy.
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

# Flexible Server VNet integration resolves the server FQDN through a private DNS
# zone linked to the VNet.
resource "azurerm_private_dns_zone" "this" {
  name                = "${var.name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "${var.name}-pg-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.postgres_version

  administrator_login    = var.administrator_login
  administrator_password = random_password.admin.result

  sku_name   = var.sku_name
  storage_mb = var.storage_mb

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id
  public_network_access_enabled = false

  backup_retention_days = 7
  zone                  = "1"

  # The DNS link must exist before the server so name resolution works.
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}

# Flexible Server blocks CREATE EXTENSION unless the extension is on this
# allow-list first — a restriction RDS doesn't have, so it never showed up on
# AWS. DBOS's system-database migration needs uuid-ossp.
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "uuid-ossp"
}

resource "azurerm_postgresql_flexible_server_database" "platform" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# The full connection string ESO reads. TLS is required by Flexible Server and
# turned on in the chart via DATABASE_SSL; the app appends the SSL option itself,
# so the URL carries only the standard fields.
resource "azurerm_key_vault_secret" "database_url" {
  name         = var.database_url_secret_name
  key_vault_id = var.key_vault_id
  value = format(
    "postgres://%s:%s@%s:5432/%s",
    var.administrator_login,
    random_password.admin.result,
    azurerm_postgresql_flexible_server.this.fqdn,
    var.database_name,
  )
}
