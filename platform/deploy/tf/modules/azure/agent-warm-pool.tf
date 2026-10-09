# ── Agent nodes ──────────────────────────────────────────────────────────────
#
# Spare agent nodes kept warm between runs (Roko CR-379), on the NAP shape
# only. Node auto-provisioning is Karpenter, so the same local chart as on AWS
# creates the `agents` NodePool, referencing the AKSNodeClass NAP provides; the
# AKS-managed KEDA add-on (aks/main.tf) scales the platform chart's placeholder
# Deployment from the API's GET /internal/agent-pool.
#
# Before the subnet grant there is no NAP and no KEDA. Agent Jobs keep the fixed
# `agents` pool, which holds one node at min_count 1 and is warm already, so
# the platform values keep the same nodePool name and leave the placeholders
# off.

locals {
  agent_node_pool_name = "agents"

  agent_node_pool_values = {
    name        = local.agent_node_pool_name
    idleTimeout = var.agent_node_idle_timeout
    nodeClassRef = {
      group = "karpenter.azure.com"
      kind  = "AKSNodeClass"
      name  = var.agent_node_class_name
    }
  }

  # Merged into the API's chart values in main.tf.
  agent_warm_pool_chart_values = {
    nodePool = local.agent_node_pool_name
    warmPool = { enabled = local.nap }
  }
}

resource "helm_release" "agent_node_pool" {
  count = local.nap ? 1 : 0

  name      = "agent-node-pool"
  chart     = "${path.module}/../agent-node-pool"
  namespace = "kube-system"

  values = [yamlencode(local.agent_node_pool_values)]

  wait            = true
  atomic          = true
  cleanup_on_fail = true

  depends_on = [module.aks]
}
