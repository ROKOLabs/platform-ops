variable "name" {
  description = "Flexible Server name — globally unique, lowercase."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_id" {
  description = "VNet to link the private DNS zone to."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "administrator_login" {
  type    = string
  default = "roko"
}

variable "database_name" {
  type    = string
  default = "platform"
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "key_vault_id" {
  description = "Vault the full DATABASE_URL is written to (Azure PG has no managed rotating secret)."
  type        = string
}

variable "database_url_secret_name" {
  description = "Key Vault secret name ESO maps to DATABASE_URL."
  type        = string
  default     = "database-url"
}

variable "tags" {
  type    = map(string)
  default = {}
}
