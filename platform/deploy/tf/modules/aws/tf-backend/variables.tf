variable "bucket_name" {
  description = "Globally unique name for the state bucket"
  type        = string
}

variable "noncurrent_version_expiration_days" {
  type    = number
  default = 90
}
