variable "name" {
  type = string
}

variable "kubernetes_version" {
  # 1.33 left EKS standard support on 2026-07-29; 1.34 is comfortably inside it.
  type    = string
  default = "1.34"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs to grant cluster-admin. Roles and users both work. Use the FULL pathful ARN — EKS rejects path-stripped SSO role ARNs as invalid principals."
  type        = list(string)
  default     = []
}

variable "viewer_principal_arns" {
  description = "IAM principal ARNs to grant cluster-wide read access (AmazonEKSViewPolicy). Same pathful-ARN rule as above."
  type        = list(string)
  default     = []
}

variable "node_pools" {
  type    = list(string)
  default = ["general-purpose", "system"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
