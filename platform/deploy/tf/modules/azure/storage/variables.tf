variable "account_name" {
  description = "Storage account name — globally unique, 3-24 lowercase alphanumerics."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "container_name" {
  description = "Blob container shared by artifacts and prototypes (analog of the S3 uploads bucket)."
  type        = string
  default     = "uploads"
}

variable "checkpoints_container_name" {
  description = "Private Blob container for agent checkpoint archives."
  type        = string
  default     = "agent-checkpoints"
}

variable "cors_origins" {
  description = "Frontend origins allowed to PUT/GET blobs directly via SAS URLs."
  type        = list(string)
  default     = ["https://platform.dev.rokolabs.ai", "http://localhost:3000"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
