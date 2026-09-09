variable "name" {
  description = "Registry name — globally unique, 5-50 alphanumerics."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sku" {
  description = "Basic/Standard/Premium. Retention policies need Premium; see retention_days."
  type        = string
  default     = "Standard"
}

variable "retention_days" {
  description = "Untagged-manifest retention in days. Applied only on the Premium SKU (no-op otherwise), the analog of the ECR untagged-expiry lifecycle rule."
  type        = number
  default     = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
