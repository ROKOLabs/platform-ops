variable "name" {
  type = string
}

variable "keep_sha_images" {
  description = "How many sha-* tagged images to keep before expiring the oldest."
  type        = number
  default     = 20
}

variable "untagged_expiry_days" {
  type    = number
  default = 7
}
