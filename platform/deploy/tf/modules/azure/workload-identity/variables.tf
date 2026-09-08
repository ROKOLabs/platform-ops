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

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer the federated credentials trust."
  type        = string
}

variable "storage_account_id" {
  description = "Scope for the api identity's Storage Blob Data Contributor grant."
  type        = string
}

variable "key_vault_id" {
  description = "Scope for the external-secrets identity's Key Vault Secrets User grant."
  type        = string
}

variable "service_namespace" {
  description = "Namespace of the roko-api ServiceAccount."
  type        = string
  default     = "service"
}

variable "api_service_account" {
  type    = string
  default = "roko-api"
}

variable "agents_namespace" {
  description = "Namespace of the agent Job ServiceAccount."
  type        = string
  default     = "agents"
}

variable "agent_service_account" {
  description = "ServiceAccount used by agent Jobs."
  type        = string
  default     = "agent"
}

variable "external_secrets_namespace" {
  type    = string
  default = "external-secrets"
}

variable "external_secrets_service_account" {
  type    = string
  default = "external-secrets"
}

variable "tags" {
  type    = map(string)
  default = {}
}
