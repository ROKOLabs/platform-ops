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
  default     = "10.180.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Subnet for AKS nodes and pods (Azure CNI gives every pod a VNet IP)."
  type        = string
  default     = "10.180.0.0/20"
}

variable "postgres_subnet_prefix" {
  description = "Delegated subnet for the PostgreSQL Flexible Server VNet integration."
  type        = string
  default     = "10.180.16.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}
