# Azure Container Registry — the analog of ECR. One registry holds every image
# repository (roko-api, roko-web), unlike ECR's one-repo-per-image model, so this
# module is created once, not per image. Admin user stays off: nodes pull via the
# kubelet identity's AcrPull role (granted by the caller), CI pushes via `az acr
# login` against its own OIDC identity.
resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = false

  # Retention of untagged manifests is a Premium-only feature; left unset on
  # Basic/Standard. This is the closest analog to ECR's untagged-expiry rule.
  retention_policy_in_days = var.sku == "Premium" ? var.retention_days : null

  tags = var.tags
}
