variable "name" {
  type = string
}

variable "keep_sha_images" {
  description = "How many sha-* tagged images to keep before expiring the oldest."
  type        = number
  default     = 20
}

variable "untagged_expiry_days" {
  description = "Days an untagged layer survives. Untagged means a layer whose tag was moved or overwritten, not a released image, and the count rule above is what bounds the tagged ones. A year rather than a week because storage here is cheap and an expiry measured in days is a decision you cannot undo when you need an old image."
  type        = number
  default     = 365
}
