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

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "aks_subnet_id" {
  description = "Subnet for fixed system nodes, NAP nodes, and pods (Azure CNI)."
  type        = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public API server. Empty list = no restriction."
  type        = list(string)
  default     = []
}

variable "zones" {
  description = "Availability zones for the fixed system pool. Empty for a region that has none."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
