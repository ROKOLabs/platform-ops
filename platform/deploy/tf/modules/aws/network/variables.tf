variable "name" {
  type = string
}

variable "cidr" {
  description = "VPC CIDR. CANNOT be changed after creation."
  type        = string
}

variable "azs" {
  type = list(string)
}

variable "single_nat_gateway" {
  description = "true for dev (one shared NAT, ~$33/mo), false for prod (one per AZ)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
