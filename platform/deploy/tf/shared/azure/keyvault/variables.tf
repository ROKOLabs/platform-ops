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

variable "authorization" {
  description = "`rbac` grants through role assignments. `access_policy` grants through vault access policies, for a principal without Microsoft.Authorization/roleAssignments/write. Changing it on an existing vault needs that same permission."
  type        = string
  default     = "rbac"

  validation {
    condition     = contains(["rbac", "access_policy"], var.authorization)
    error_message = "authorization must be \"rbac\" or \"access_policy\"."
  }
}

variable "admin_object_ids" {
  description = "Object IDs granted full secret access: Key Vault Secrets Officer under `rbac`, an access policy under `access_policy`. Typically the Terraform principal."
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
