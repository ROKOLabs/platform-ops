variable "role_name" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_org_id" {
  description = "Numeric GitHub org ID (gh api orgs/<org> --jq .id). GitHub's sub claim is org@ID/repo@ID."
  type        = string
}

variable "github_repo_id" {
  description = "Numeric GitHub repo ID (gh api repos/<org>/<repo> --jq .id)"
  type        = string
}

variable "allowed_subjects" {
  description = "OIDC sub claims allowed to assume this role. NEVER wildcard org/repo."
  type        = list(string)
  default     = null
}

variable "policy_arns" {
  type    = list(string)
  default = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "create_oidc_provider" {
  description = "false if the provider already exists — it is an ACCOUNT-WIDE singleton"
  type        = bool
  default     = true
}
