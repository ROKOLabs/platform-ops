variable "name" {
  description = "Key Vault name — globally unique, 3-24 alphanumerics/hyphens."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "admin_object_ids" {
  description = "Object IDs granted Key Vault Secrets Officer. Typically the Terraform principal."
  type        = list(string)
  default     = []
}

variable "soft_delete_retention_days" {
  description = "How long a deleted vault keeps its name reserved. Seven is Azure's minimum."
  type        = number
  default     = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
