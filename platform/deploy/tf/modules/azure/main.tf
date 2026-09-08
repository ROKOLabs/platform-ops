# The Azure half of the pair: one composed module a deployment names once. It
# owns the resource group, network, cluster, database, object storage, registry,
# secrets, model deployments, and the Helm releases that run the platform.
#
# It is a separate implementation from `modules/aws` on purpose. The two clouds
# install the same chart but hand it different values, because the API selects
# its storage backend, its secret backend and its workload identity from them.

locals {
  tags = merge(
    {
      Project   = var.name
      ManagedBy = "terraform"
    },
    var.tags,
  )

  image_tag = var.image_tag != "" ? var.image_tag : local.platform_version

  cors_origins = length(var.artifact_cors_origins) > 0 ? var.artifact_cors_origins : ["https://${var.ingress_host}"]
}

data "azurerm_client_config" "current" {}

# One resource group holds the whole deployment.
resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = local.tags
}

# ── Network and cluster ──────────────────────────────────────────────────────

module "vnet" {
  source = "./vnet"

  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_cidr
  tags                = local.tags
}

module "aks" {
  source = "./aks"

  name                 = var.name
  location             = azurerm_resource_group.this.location
  resource_group_name  = azurerm_resource_group.this.name
  kubernetes_version   = var.kubernetes_version
  aks_subnet_id        = module.vnet.aks_subnet_id
  api_allowed_cidrs    = var.api_allowed_cidrs
  agent_node_vm_size   = var.agent_node_vm_size
  agent_node_min_count = var.agent_node_min_count
  agent_node_max_count = var.agent_node_max_count
  tags                 = local.tags
}

# ── Data plane ───────────────────────────────────────────────────────────────

module "storage" {
  source = "./storage"

  account_name               = var.storage_account_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  container_name             = var.uploads_container_name
  checkpoints_container_name = var.checkpoints_container_name
  cors_origins               = local.cors_origins
  tags                       = local.tags
}

module "acr" {
  source = "./acr"

  name                = var.acr_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "keyvault" {
  source = "./keyvault"

  name                = var.key_vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # The Terraform principal writes the database URL and the encryption key below,
  # so it needs Secrets Officer on the vault it just created.
  admin_object_ids = concat(
    [data.azurerm_client_config.current.object_id],
    var.extra_secrets_officer_object_ids,
  )

  tags = local.tags
}

module "postgres" {
  source = "./postgres"

  name                = var.postgres_server_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_id             = module.vnet.vnet_id
  delegated_subnet_id = module.vnet.postgres_subnet_id
  key_vault_id        = module.keyvault.vault_id
  tags                = local.tags

  # The Secrets Officer grant must exist before Terraform writes the DATABASE_URL
  # secret into the vault.
  depends_on = [module.keyvault]
}

module "workload_identity" {
  source = "./workload-identity"

  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  oidc_issuer_url     = module.aks.oidc_issuer_url
  storage_account_id  = module.storage.account_id
  key_vault_id        = module.keyvault.vault_id
  tags                = local.tags
}

module "foundry" {
  source = "./foundry"

  account_name      = var.foundry.account_name
  location          = coalesce(var.foundry.location, azurerm_resource_group.this.location)
  resource_group_id = azurerm_resource_group.this.id
  project_name      = var.foundry.project_name

  gpt_deployment_enabled  = var.foundry.gpt_deployment_enabled
  gpt_deployment_name     = var.foundry.gpt_deployment_name
  gpt_deployment_sku      = var.foundry.gpt_deployment_sku
  gpt_deployment_capacity = var.foundry.gpt_deployment_capacity
  gpt_model_version       = var.foundry.gpt_model_version

  deployment_enabled  = var.foundry.claude_enabled
  deployment_name     = var.foundry.claude_deployment_name
  deployment_sku      = var.foundry.claude_deployment_sku
  deployment_capacity = var.foundry.claude_capacity
  organization_name   = var.foundry.organization_name
  country_code        = var.foundry.country_code
  industry            = var.foundry.industry

  tags = local.tags
}

# Nodes pull images with the kubelet identity, the analog of granting the node
# role ECR pull access on AWS.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = module.acr.registry_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

# ── Secrets ──────────────────────────────────────────────────────────────────
#
# The database URL is written by `./postgres`. The encryption key is generated
# here, so a fresh deployment cannot silently ship without it.

resource "random_bytes" "secret_encryption_key" {
  length = 32
}

# The chart's ExternalSecret reads SECRET_ENCRYPTION_KEY out of this JSON, so the
# shape is part of the contract.
resource "azurerm_key_vault_secret" "secret_encryption" {
  name         = "api-secret-encryption"
  key_vault_id = module.keyvault.vault_id
  value        = jsonencode({ SECRET_ENCRYPTION_KEY = random_bytes.secret_encryption_key.base64 })

  depends_on = [module.keyvault]
}

# ── In-cluster baseline ──────────────────────────────────────────────────────

module "cluster_config" {
  source = "./cluster-config"

  chart_version              = var.external_secrets_chart_version
  external_secrets_client_id = module.workload_identity.external_secrets_client_id
}

# ── Origin TLS ───────────────────────────────────────────────────────────────
#
# ingress-nginx terminates TLS from a Kubernetes Secret, so on Azure Terraform
# writes the certificate straight into that Secret. No secret store and no
# External Secrets round trip: Terraform is the thing that generated it.
resource "tls_private_key" "origin" {
  count = var.tls_mode == "self_signed" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "origin" {
  count = var.tls_mode == "self_signed" ? 1 : 0

  private_key_pem = tls_private_key.origin[0].private_key_pem

  subject {
    common_name  = var.ingress_host
    organization = var.name
  }

  dns_names = [var.ingress_host]

  # Ten years, no early renewal, so the certificate is stable across applies.
  validity_period_hours = 87600
  early_renewal_hours   = 0

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "kubernetes_secret_v1" "origin_tls" {
  metadata {
    name      = "roko-platform-tls"
    namespace = module.cluster_config.service_namespace
  }

  type = "kubernetes.io/tls"

  data = var.tls_mode == "self_signed" ? {
    "tls.crt" = tls_self_signed_cert.origin[0].cert_pem
    "tls.key" = tls_private_key.origin[0].private_key_pem
    } : {
    "tls.crt" = ""
    "tls.key" = ""
  }

  # `provided` serves whatever is dropped in, so the value stops being
  # Terraform's after the Secret exists.
  lifecycle {
    ignore_changes = [data]
  }
}

# ── Origin access ────────────────────────────────────────────────────────────

data "http" "cloudflare_ips" {
  count = var.restrict_origin_to_cloudflare ? 1 : 0

  url = "https://api.cloudflare.com/client/v4/ips"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  cloudflare_ips = var.restrict_origin_to_cloudflare ? jsondecode(data.http.cloudflare_ips[0].response_body).result : null

  origin_ipv4_cidrs = var.restrict_origin_to_cloudflare ? concat(local.cloudflare_ips.ipv4_cidrs, var.extra_origin_cidrs) : []
  origin_ipv6_cidrs = var.restrict_origin_to_cloudflare ? local.cloudflare_ips.ipv6_cidrs : []
}

# ── Ingress controller ───────────────────────────────────────────────────────
#
# AKS has no built-in load balancer controller, so the module installs the one
# the chart's Ingress names. `loadBalancerSourceRanges` is where the Cloudflare
# restriction lands on this cloud: the Azure load balancer, not an annotation.
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [yamlencode({
    controller = {
      service = {
        loadBalancerSourceRanges = concat(local.origin_ipv4_cidrs, local.origin_ipv6_cidrs)
      }
    }
  })]
}

# ── The platform itself ──────────────────────────────────────────────────────

locals {
  platform_values = {
    api = {
      image = {
        repository = "${var.image_registry}/${var.image_names.api}"
        tag        = local.image_tag
      }

      hostingProvider = "azure"
      publicUrl       = "https://${var.ingress_host}"

      # Object storage is Azure Blob. Credentials come from Workload Identity, so
      # no key is set anywhere.
      storage = {
        provider     = "azure"
        azureAccount = module.storage.account_name
      }

      artifacts = { bucket = module.storage.container_name }

      # Secrets come from Key Vault through the ESO controller's federated
      # identity.
      secrets = {
        provider      = "azurekv"
        storeName     = "azure-key-vault"
        azureVaultUrl = module.keyvault.vault_uri
      }

      # The client id of the user-assigned identity, not its principal id: Entra
      # rejects the object id with AADSTS700016.
      workloadIdentity = { clientId = module.workload_identity.api_client_id }

      # Azure PostgreSQL Flexible Server has no managed rotating secret, so
      # Terraform writes the whole postgres:// URL to this Key Vault secret and
      # ESO maps it straight to DATABASE_URL. host, port and secretArn are unused
      # on this path.
      db = {
        secretName = module.postgres.database_url_secret_name
        ssl        = true
      }

      secretEncryption = { secretName = azurerm_key_vault_secret.secret_encryption.name }

      # Bedrock is unreachable from AKS: the pod has no AWS identity.
      modelProviders = { allowedKinds = "azure-openai" }

      agents = {
        image            = "${var.image_registry}/${var.image_names.agent}:${local.image_tag}"
        nodePool         = "agents"
        checkpointBucket = module.storage.checkpoints_container_name
        maxConcurrency   = var.agent_node_max_count

        # A D2s_v5 exposes about 7Gi after AKS reservations, so an 8Gi agent
        # cannot schedule there. One three-CPU agent plus the DaemonSets fits a
        # four-vCPU, 16Gi D4s_v5, and memory keeps it to one agent per node.
        cpu              = "3"
        memory           = "8Gi"
        ephemeralStorage = "8Gi"

        # Agent Jobs reuse the API identity, whose Storage Blob Data Contributor
        # role is scoped to this storage account.
        workloadIdentity = { clientId = module.workload_identity.api_client_id }
      }
    }

    web = {
      image = {
        repository = "${var.image_registry}/${var.image_names.web}"
        tag        = local.image_tag
      }
    }

    ingress = {
      host = var.ingress_host

      # ingress-nginx creates the `nginx` IngressClass itself, so this chart
      # must not.
      ingressClassName   = "nginx"
      createIngressClass = false

      ingressAnnotations = {
        # Prototype bundle uploads stream through the API; raise nginx's 1m
        # default past the 50 MB per-flavor cap. Artifact uploads go direct to
        # Blob via SAS and never traverse the ingress.
        "nginx.ingress.kubernetes.io/proxy-body-size" = "100m"
      }

      tls = { secretName = kubernetes_secret_v1.origin_tls.metadata[0].name }
    }
  }
}

resource "helm_release" "platform" {
  name       = "roko-platform"
  repository = "oci://registry-1.docker.io/rokoplatform"
  chart      = "roko-platform"
  version    = local.platform_version
  namespace  = module.cluster_config.service_namespace

  values = [
    yamlencode(local.platform_values),
    yamlencode(var.chart_values),
  ]

  # The chart templates a SecretStore and two ExternalSecrets, so the operator's
  # CRDs have to be registered before Helm applies them.
  depends_on = [
    module.cluster_config,
    helm_release.ingress_nginx,
  ]
}
