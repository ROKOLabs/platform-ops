variable "name" {
  description = "Name prefix for every resource this module creates, for example `acme-prod`."
  type        = string
}

variable "region" {
  description = "AWS region. Must match the region the calling provider is configured for."
  type        = string
}

variable "ingress_host" {
  description = "Public hostname the platform serves, for example `eyeq.rokolabs.ai`. It names the Ingress host rule and the origin certificate."
  type        = string
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Required, with no default, because the only safe default is the one somebody chose: an open control plane is a decision, not an accident. Terraform itself reaches the cluster through this endpoint, so the address applying this module has to be in the list."
  type        = list(string)
}

# ── Network ──────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "VPC CIDR. Cannot be changed after creation. A /20 gives each zone a /22 for pods and a /24 for load balancers, which is ample for this platform; widen it only for a deployment that will run much more in the cluster."
  type        = string
  default     = "10.0.0.0/20"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per zone, in the same order as `azs`. Empty derives them from `vpc_cidr`. Set them only to match subnets that already exist."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per zone, in the same order as `azs`. Empty derives them from `vpc_cidr`."
  type        = list(string)
  default     = []
}

variable "azs" {
  description = "Availability zones. One private /20 and one public /24 subnet are created per zone."
  type        = list(string)
}

variable "high_availability" {
  description = "One switch for the two places a deployment trades cost against surviving the loss of a zone: on runs a NAT gateway per zone rather than one shared, and a standby database in a second zone. Off is the default because losing a zone is rare and both cost real money every month; turn it on for a deployment whose downtime costs more than the standby does."
  type        = bool
  default     = false
}

# ── Cluster access ───────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "EKS Kubernetes version. 1.36 leaves standard support in August 2027; a version already near its end date puts a deployment into an upgrade or into extended-support pricing shortly after it is created."
  type        = string
  default     = "1.36"
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster admin. Use the FULL pathful ARN: EKS rejects path-stripped SSO role ARNs as invalid principals."
  type        = list(string)
  default     = []
}

variable "viewer_role_arns" {
  description = "IAM role ARNs granted cluster-wide read access. Same pathful-ARN rule as above."
  type        = list(string)
  default     = []
}

# ── TLS ──────────────────────────────────────────────────────────────────────

variable "tls_mode" {
  description = "`self_signed` generates the origin certificate during the apply and imports it into ACM; the deployment sits behind Cloudflare, which presents the certificate a browser checks. `provided` uses the ACM certificate named by `tls_certificate_arn` instead and generates nothing."
  type        = string
  default     = "self_signed"

  validation {
    condition     = contains(["self_signed", "provided"], var.tls_mode)
    error_message = "tls_mode must be `self_signed` or `provided`."
  }
}

variable "tls_certificate_arn" {
  description = "ACM certificate ARN the load balancer serves. Required when `tls_mode` is `provided`, ignored otherwise."
  type        = string
  default     = ""

  validation {
    condition     = var.tls_mode != "provided" || var.tls_certificate_arn != ""
    error_message = "tls_certificate_arn is required when tls_mode is `provided`."
  }
}

variable "restrict_origin_to_cloudflare" {
  description = "true restricts the load balancer to Cloudflare's published address ranges, read from https://api.cloudflare.com/client/v4/ips during the apply. It is what makes an unvalidated Cloudflare-to-origin hop acceptable, so leave it on unless the deployment does not sit behind Cloudflare."
  type        = bool
  default     = true
}

variable "extra_origin_cidrs" {
  description = "Additional IPv4 CIDRs allowed to reach the load balancer, on top of Cloudflare's. Use it to reach a locked-down origin directly for debugging."
  type        = list(string)
  default     = []
}

# ── Database ─────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "Postgres instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Postgres storage in GiB."
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "Postgres major version, or a full minor version to pin one. AWS resolves a major to its current minor and keeps it there through the maintenance window."
  type        = string
  default     = "17"
}

variable "db_apply_immediately" {
  description = "false applies an instance class, storage or credential change in the next maintenance window. true applies it at once, with the reboot that implies, which is what a deployment nobody depends on wants and a deployment somebody depends on does not."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "true refuses to destroy the instance until it is turned off and applied."
  type        = bool
  default     = true
}

# ── Images and chart ─────────────────────────────────────────────────────────

variable "image_registry" {
  description = "Registry the chart pulls images from."
  type        = string
  default     = "docker.io/rokoplatform"
}

variable "image_names" {
  description = "Repository name of each image inside `image_registry`. The defaults are what release.yml publishes to Docker Hub; a deployment that builds its own images into ECR names its own repositories here."
  type = object({
    api   = optional(string, "api")
    web   = optional(string, "web")
    agent = optional(string, "agent")
  })
  default = {}
}

variable "image_tag" {
  description = "Image tag. Empty means the module's own version, which is the release it deploys. Set only by a lane that builds its own images."
  type        = string
  default     = ""
}

variable "chart_values" {
  description = "Chart values merged over the values the module computes. The merge is deep, so overriding one nested key leaves its siblings in place."
  type        = any
  default     = {}
}

# ── Names ────────────────────────────────────────────────────────────────────
#
# Every name defaults to one derived from `name`, which is what a new deployment
# wants. They are overridable because a bucket name and a repository name are
# both force-new and a bucket holding objects cannot be renamed, so a deployment
# adopting resources that already exist has to be able to state their names
# rather than move their contents.

variable "uploads_bucket_name" {
  description = "Uploads bucket. Empty means `<name>-uploads`."
  type        = string
  default     = ""
}

variable "checkpoints_bucket_name" {
  description = "Agent checkpoints bucket. Empty means `<name>-agent-checkpoints`."
  type        = string
  default     = ""
}

variable "ecr_repository_names" {
  description = "ECR repository per image. Each unset key means `<name>-<key>`."
  type = object({
    api   = optional(string)
    web   = optional(string)
    agent = optional(string)
  })
  default = {}
}

variable "artifact_cors_origins" {
  description = "Browser origins allowed to PUT/GET the uploads bucket through presigned URLs. Empty means the deployment's own `https://<ingress_host>` alone."
  type        = list(string)
  default     = []
}

# ── Agents ───────────────────────────────────────────────────────────────────

variable "agent_bedrock_model_arns" {
  description = "Bedrock model and inference-profile ARNs the agent role may invoke. The model catalogue changes at the speed of vendor releases, so the default covers any model in the account; the boundary doing the work is the run's isolated namespace."
  type        = list(string)
  default = [
    "arn:aws:bedrock:*::foundation-model/*",
    "arn:aws:bedrock:*:*:inference-profile/*",
  ]
}

variable "agent_checkpoint_prefix" {
  description = "Key prefix the agent supervisor writes run checkpoints under. Both IAM grants are scoped to it."
  type        = string
  default     = "runs"
}

variable "agent_checkpoint_expiration_days" {
  description = "Backstop expiry for checkpoint objects the backend's own cleanup and daily sweep did not remove."
  type        = number
  default     = 30
}

# ── Budget ───────────────────────────────────────────────────────────────────

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD. Null creates no budget."
  type        = number
  default     = null
}

variable "budget_notify_emails" {
  description = "Addresses the budget alerts. Required when `monthly_budget_usd` is set."
  type        = list(string)
  default     = []

  validation {
    condition     = var.monthly_budget_usd == null || length(var.budget_notify_emails) > 0
    error_message = "budget_notify_emails is required when monthly_budget_usd is set."
  }
}

# ── Misc ─────────────────────────────────────────────────────────────────────

variable "external_secrets_chart_version" {
  description = "external-secrets chart version installed into the cluster."
  type        = string
  default     = "2.8.0"
}

variable "tags" {
  description = "Tags added to every taggable resource."
  type        = map(string)
  default     = {}
}
