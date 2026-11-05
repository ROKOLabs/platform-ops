variable "cluster_name" {
  type = string
}

variable "chart_version" {
  type = string
}

variable "namespace" {
  type    = string
  default = "external-secrets"
}

variable "role_name" {
  description = "Name of the IAM role the ESO controller assumes via Pod Identity."
  type        = string
}

variable "secret_arn_patterns" {
  description = "Secrets Manager ARNs (wildcards allowed) the operator may read."
  type        = list(string)
}
