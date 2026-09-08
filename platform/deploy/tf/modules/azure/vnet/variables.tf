variable "name" {
  description = "Resource name prefix, e.g. rokolabs-dev."
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "address_space" {
  description = "VNet CIDR. CANNOT be changed after creation."
  type        = string
  default     = "10.0.0.0/22"
}

variable "aks_subnet_prefix" {
  description = "Subnet for AKS nodes and pods (Azure CNI gives every pod a VNet IP). Empty takes the first half of `address_space`."
  type        = string
  default     = ""
}

variable "postgres_subnet_prefix" {
  description = "Delegated subnet for the PostgreSQL Flexible Server VNet integration. Empty takes a sixteenth of `address_space`, at the top of the range."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
