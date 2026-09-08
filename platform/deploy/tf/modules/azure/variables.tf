variable "name" {
  description = "Name prefix for every resource this module creates, and the resource group's name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "ingress_host" {
  description = "Public hostname the platform serves. It names the Ingress host rule and the origin certificate."
  type        = string
}

# ── Network and cluster ──────────────────────────────────────────────────────

variable "vnet_cidr" {
  description = "VNet address space. CANNOT be changed after creation."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the AKS public API server. Empty means open."
  type        = list(string)
  default     = []
}

variable "agent_node_vm_size" {
  description = "VM size for the autoscaling agent user pool. A D4s_v5 has room for one three-CPU agent Job plus the AKS DaemonSets."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "agent_node_min_count" {
  description = "Minimum number of warm agent nodes."
  type        = number
  default     = 1
}

variable "agent_node_max_count" {
  description = "Maximum number of autoscaled agent nodes. Memory limits each node to one agent, so this is also the concurrency ceiling."
  type        = number
  default     = 3
}

# ── Globally unique resource names ───────────────────────────────────────────

variable "storage_account_name" {
  description = "Uploads storage account. Globally unique, 3-24 lowercase alphanumerics."
  type        = string
}

variable "acr_name" {
  description = "Container registry. Globally unique, 5-50 alphanumerics."
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault. Globally unique, 3-24 alphanumerics and hyphens."
  type        = string
}

variable "postgres_server_name" {
  description = "PostgreSQL Flexible Server. Globally unique, lowercase."
  type        = string
}

# ── TLS ──────────────────────────────────────────────────────────────────────

variable "tls_mode" {
  description = "`self_signed` generates the origin certificate during the apply and writes it straight to the TLS Secret ingress-nginx reads; the deployment sits behind Cloudflare, which presents the certificate a browser checks. `provided` creates that Secret empty, ignores its value from then on, and serves whatever is dropped into it."
  type        = string
  default     = "self_signed"

  validation {
    condition     = contains(["self_signed", "provided"], var.tls_mode)
    error_message = "tls_mode must be `self_signed` or `provided`."
  }
}

variable "restrict_origin_to_cloudflare" {
  description = "true restricts the ingress load balancer to Cloudflare's published address ranges, read from https://api.cloudflare.com/client/v4/ips during the apply."
  type        = bool
  default     = true
}

variable "extra_origin_cidrs" {
  description = "Additional CIDRs allowed to reach the load balancer, on top of Cloudflare's."
  type        = list(string)
  default     = []
}

variable "ingress_nginx_chart_version" {
  description = "ingress-nginx chart version. The AKS path has no cloud load balancer controller of its own, so the module installs the controller the Ingress names."
  type        = string
  default     = "4.11.3"
}

# ── Images and chart ─────────────────────────────────────────────────────────

variable "image_registry" {
  description = "Registry the chart pulls images from."
  type        = string
  default     = "docker.io/rokoplatform"
}

variable "image_names" {
  description = "Repository name of each image inside `image_registry`."
  type = object({
    api   = optional(string, "api")
    web   = optional(string, "web")
    agent = optional(string, "agent")
  })
  default = {}
}

variable "image_tag" {
  description = "Image tag. Empty means the module's own version, which is the release it deploys."
  type        = string
  default     = ""
}

variable "chart_values" {
  description = "Chart values merged over the values the module computes. The merge is deep."
  type        = any
  default     = {}
}

# ── Container names ──────────────────────────────────────────────────────────
#
# The account, registry, vault and server names above are required because they
# are globally unique. These two are not, so they default, and are overridable
# for the same reason as their AWS counterparts: a deployment adopting a
# container that already holds objects has to be able to name it.

variable "uploads_container_name" {
  description = "Blob container shared by artifacts and prototypes."
  type        = string
  default     = "uploads"
}

variable "checkpoints_container_name" {
  description = "Private Blob container for agent checkpoint archives."
  type        = string
  default     = "agent-checkpoints"
}

variable "artifact_cors_origins" {
  description = "Browser origins allowed to PUT/GET the uploads container through SAS URLs. Empty means the deployment's own `https://<ingress_host>` alone."
  type        = list(string)
  default     = []
}

# ── Model deployments ────────────────────────────────────────────────────────

variable "foundry" {
  description = "Microsoft Foundry account, project and model deployments. `azure-openai` is the only provider kind an AKS pod can authenticate, so the GPT deployment is what the platform actually serves. The Claude deployment stays off: no provider kind can address it, and Azure Marketplace does not support CSP subscriptions."
  type = object({
    account_name            = string
    project_name            = string
    location                = optional(string)
    organization_name       = optional(string, "ROKO Labs")
    country_code            = optional(string, "US")
    industry                = optional(string, "technology")
    gpt_deployment_enabled  = optional(bool, true)
    gpt_deployment_name     = optional(string, "gpt-5.4-mini")
    gpt_deployment_sku      = optional(string, "GlobalStandard")
    gpt_deployment_capacity = optional(number, 24000)
    gpt_model_version       = optional(string)
    claude_enabled          = optional(bool, false)
    claude_deployment_name  = optional(string, "claude-sonnet-5")
    claude_deployment_sku   = optional(string, "GlobalStandard")
    claude_capacity         = optional(number, 25)
  })
}

# ── Misc ─────────────────────────────────────────────────────────────────────

variable "extra_secrets_officer_object_ids" {
  description = "Additional principals granted Key Vault Secrets Officer, on top of the Terraform principal."
  type        = list(string)
  default     = []
}

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
