# ── Render nodes ─────────────────────────────────────────────────────────────
#
# Render Jobs (Roko CR-475): the API runs a headless Chromium per Status
# Report PDF or prototype thumbnail, each in its own Job in the `renders`
# namespace (cluster-config), never in the API pod.
#
# On the NAP shape the same local chart as the agents pool creates a
# dedicated `renders` NodePool, and `render_warm_spares` placeholder pods keep
# render-sized room on it. Before the subnet grant there is no NAP: render
# Jobs set no node pool and run on the default pool, with no placeholders.
#
# A render pod has no service account token and no cloud identity: the API
# reads the result over DevTools and stores it itself, so nothing here grants
# storage access or adds a federated credential.

locals {
  render_node_pool_name = "renders"

  render_node_pool_values = {
    name        = local.render_node_pool_name
    idleTimeout = var.agent_node_idle_timeout
    nodeClassRef = {
      group = "karpenter.azure.com"
      kind  = "AKSNodeClass"
      name  = var.agent_node_class_name
    }
  }

  # The API's chart values (main.tf). An older chart ignores the key.
  render_chart_values = {
    enabled    = true
    namespace  = module.cluster_config.renders_namespace
    secretName = azurerm_key_vault_secret.render.name
    nodePool   = local.nap ? local.render_node_pool_name : ""
    warmPool = {
      enabled = local.nap && var.render_warm_spares > 0
      spares  = var.render_warm_spares
    }
  }
}

resource "helm_release" "render_node_pool" {
  count = local.nap ? 1 : 0

  name      = "render-node-pool"
  chart     = "${path.module}/../agent-node-pool"
  namespace = "kube-system"

  values = [yamlencode(local.render_node_pool_values)]

  wait            = true
  atomic          = true
  cleanup_on_fail = true

  depends_on = [module.aks]
}

# Generated here, not by hand: nothing outside the API needs the value, and
# replacing it only voids render links already issued, which expire in ten
# minutes.
resource "random_password" "render_secret" {
  length  = 48
  special = false
}

# The chart's ExternalSecret reads RENDER_SECRET out of this JSON, so the shape
# is part of the contract.
resource "azurerm_key_vault_secret" "render" {
  name         = "api-render"
  key_vault_id = module.keyvault.vault_id
  value        = jsonencode({ RENDER_SECRET = random_password.render_secret.result })

  # The grant must exist and have propagated, as for the encryption key.
  depends_on = [module.keyvault]
}
