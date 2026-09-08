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

variable "tags" {
  type    = map(string)
  default = {}
}
