variable "name" {
  type = string
}

variable "cidr" {
  description = "VPC CIDR. CANNOT be changed after creation."
  type        = string
  default     = "10.0.0.0/20"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per zone, in the same order as `azs`. Empty derives them from `cidr`. Set them only to match subnets that already exist, because changing a subnet's range replaces it and everything attached to it."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per zone, in the same order as `azs`. Empty derives them from `cidr`."
  type        = list(string)
  default     = []
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
