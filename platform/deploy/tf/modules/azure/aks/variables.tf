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
  description = "Subnet the node pool and pods live in (Azure CNI)."
  type        = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "agent_node_vm_size" {
  description = "VM size for the autoscaling agent user pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "agent_node_min_count" {
  description = "Minimum agent nodes. Keep one warm because run health checks time out after three minutes."
  type        = number
  default     = 1

  validation {
    condition     = var.agent_node_min_count >= 1
    error_message = "agent_node_min_count must be at least 1."
  }
}

variable "agent_node_max_count" {
  description = "Maximum agent nodes available to burst workloads."
  type        = number
  default     = 3

  validation {
    condition     = var.agent_node_max_count >= 1
    error_message = "agent_node_max_count must be at least 1."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public API server. Empty list = no restriction."
  type        = list(string)
  default     = []
}

variable "zones" {
  description = "Availability zones both node pools are spread across. Empty for a region that has none."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
