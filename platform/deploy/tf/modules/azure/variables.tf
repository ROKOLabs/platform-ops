variable "name" {
  description = "The resource group's name, and the default prefix for the resources inside it."
  type        = string
}

variable "resource_prefix" {
  description = "Name prefix for the resources inside the group, when they should not be named after it. Empty uses `name`. Every name it feeds is force-new, so setting it on a deployment that already exists rebuilds the VNet, the cluster and the database with it."
  type        = string
  default     = ""
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
  description = "VNet address space. CANNOT be changed after creation. A /20 gives AKS a /21 for nodes and pods and Postgres a /24; widen it only for a deployment that will run much more in the cluster."
  type        = string
  default     = "10.0.0.0/20"
}

variable "aks_subnet_cidr" {
  description = "Subnet for AKS nodes and pods. Empty derives it from `vnet_cidr`. Set it only to match a subnet that already exists."
  type        = string
  default     = ""
}

variable "postgres_subnet_cidr" {
  description = "Delegated subnet for the PostgreSQL Flexible Server. Empty derives it from `vnet_cidr`."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.36"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the AKS public API server. Required, with no default, because the only safe default is the one somebody chose. Terraform itself reaches the cluster through this endpoint, so the address applying this module has to be in the list."
  type        = list(string)
}

variable "zones" {
  description = "Availability zones for the fixed AKS system pool and the database. NAP chooses application-node zones. Empty for a region with no zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "high_availability" {
  description = "Run a standby database in a second zone. Off by default; it needs a General Purpose or Memory Optimized `postgres_sku_name`, because a Burstable server cannot run a standby at all."
  type        = bool
  default     = false
}

variable "postgres_sku_name" {
  description = "Flexible Server SKU. Burstable (B_*) is the cheap default and cannot run a standby."
  type        = string
  default     = "B_Standard_B1ms"
}

# ── Globally unique resource names ───────────────────────────────────────────

variable "storage_account_name" {
  description = "Uploads storage account. Globally unique, 3-24 lowercase alphanumerics."
  type        = string
}

variable "acr_name" {
  description = "Container registry. Globally unique, 5-50 alphanumerics. Ignored when `acr_enabled` is false."
  type        = string
  default     = ""
}

variable "acr_enabled" {
  description = "Create the container registry and grant the kubelet AcrPull on it. A deployment that pulls the published images from Docker Hub needs neither, and the grant is a role assignment a Contributor-only principal cannot make."
  type        = bool
  default     = true

  validation {
    condition     = !var.acr_enabled || var.acr_name != ""
    error_message = "acr_name is required when acr_enabled is true."
  }
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

variable "ingress_nginx_external_traffic_policy" {
  description = "externalTrafficPolicy of the controller's LoadBalancer Service. `Cluster` is the chart's default. `Local` preserves the client address at the cost of an uneven spread across nodes; the Service is patched in place, so changing it keeps the load balancer IP."
  type        = string
  default     = "Cluster"

  validation {
    condition     = contains(["Cluster", "Local"], var.ingress_nginx_external_traffic_policy)
    error_message = "ingress_nginx_external_traffic_policy must be \"Cluster\" or \"Local\"."
  }
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

# ── Telemetry ────────────────────────────────────────────────────────────────

variable "telemetry" {
  description = "OpenTelemetry Collector that exports app telemetry, pod and node CPU and memory, cluster state, Postgres statistics and Flexible Server host metrics to an OTLP endpoint. On by default, sending to `https://otlp.rokolabs.ai`, which accepts `http/protobuf` only. `protocol` is `http/protobuf` or `grpc`. `header_names` are the headers sent with every export; their values come from the `telemetry_headers_secret` secret, never from Terraform. `deployment_name` is the `roko.deployment` attribute on every signal; null means `resource_prefix`, or `name` when that is empty."
  type = object({
    enabled         = optional(bool, true)
    endpoint        = optional(string, "https://otlp.rokolabs.ai")
    protocol        = optional(string, "http/protobuf")
    header_names    = optional(list(string), ["api-key"])
    deployment_name = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^https?://.+", var.telemetry.endpoint))
    error_message = "telemetry.endpoint must be an http:// or https:// URL."
  }

  validation {
    condition     = contains(["http/protobuf", "grpc"], var.telemetry.protocol)
    error_message = "telemetry.protocol must be \"http/protobuf\" or \"grpc\"."
  }
}

# ── Misc ─────────────────────────────────────────────────────────────────────

variable "roles_granted_by_client" {
  description = "null: Terraform creates the AKS subnet role assignment, which needs Microsoft.Authorization/roleAssignments/write on the subnet (the default). A set: the client creates it by hand, and each entry names a row of `required_role_assignments` that is in place. The only key is `aks-subnet`; without it the cluster keeps the pre-NAP shape of system-assigned identity, fixed `agents` pool, and no node auto-provisioning. Never remove a key; the plan then tears down what depends on it. See \"Clients that grant roles themselves\" in the README."
  type        = set(string)
  default     = null

  validation {
    condition = var.roles_granted_by_client == null || alltrue([
      for role in var.roles_granted_by_client : contains(["aks-subnet"], role)
    ])
    error_message = "roles_granted_by_client accepts only \"aks-subnet\"."
  }
}

variable "key_vault_authorization" {
  description = "How the vault authorizes. `rbac` grants through role assignments and needs Microsoft.Authorization/roleAssignments/write from the principal applying the module. `access_policy` grants through vault access policies, which Contributor alone can write. Switching an existing vault between the two needs roleAssignments/write in either direction, so choose before the first apply."
  type        = string
  default     = "rbac"

  validation {
    condition     = contains(["rbac", "access_policy"], var.key_vault_authorization)
    error_message = "key_vault_authorization must be \"rbac\" or \"access_policy\"."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "How long a deleted vault, and a deleted secret in it, can be recovered. 7 to 90. Seven is Azure's minimum and keeps the name-reservation trap short; a deployment holding secrets seeded by hand may want longer."
  type        = number
  default     = 7

  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "key_vault_soft_delete_retention_days must be between 7 and 90."
  }
}

variable "extra_secrets_officer_object_ids" {
  description = "Additional principals granted full secret access (Key Vault Secrets Officer under `rbac`, an access policy under `access_policy`), on top of the Terraform principal."
  type        = list(string)
  default     = []
}

variable "agent_node_idle_timeout" {
  description = "How long an empty node on the agents NodePool stays up before node auto-provisioning removes it, as a Karpenter duration (`consolidateAfter`). NAP shape only."
  type        = string
  default     = "30s"

  validation {
    condition     = can(regex("^[0-9]+(ns|us|µs|ms|s|m|h)$", var.agent_node_idle_timeout))
    error_message = "agent_node_idle_timeout must be a Karpenter duration such as \"30s\" or \"1h\"."
  }
}

variable "agent_node_class_name" {
  description = "The AKSNodeClass the agents NodePool provisions from. Node auto-provisioning creates `default`. NAP shape only."
  type        = string
  default     = "default"
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
