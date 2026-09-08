variable "chart_version" {
  description = "external-secrets Helm chart version (matches the AWS cluster-config pin)."
  type        = string
  default     = "2.8.0"
}

variable "external_secrets_client_id" {
  description = "Client id of the user-assigned identity federated to the external-secrets SA (Key Vault Secrets User)."
  type        = string
}

variable "external_secrets_namespace" {
  type    = string
  default = "external-secrets"
}

variable "service_namespace" {
  type    = string
  default = "service"
}

variable "agents_namespace" {
  type    = string
  default = "agents"
}
