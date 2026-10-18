# ── Render nodes ─────────────────────────────────────────────────────────────
#
# Render Jobs (Roko CR-475): the API runs a headless Chromium per Status
# Report PDF or prototype thumbnail, each in its own Job in the `renders`
# namespace, never in the API pod. Four parts:
#
#   renders namespace  Where the API creates the Jobs. The platform chart
#                      renders the API's Role, a NetworkPolicy, the prepull
#                      DaemonSet and the placeholders into it.
#   renders NodePool   A dedicated Karpenter pool, from the same local
#                      ../agent-node-pool chart as the agents pool. Render pods
#                      open member-supplied prototype HTML in a Chromium that
#                      runs without its sandbox, so they get their own nodes.
#   signing secret     The key the API signs a render link with. The page in
#                      the Job reads its data back through that link.
#   warm spares        `render_warm_spares` placeholder pods the size of one
#                      render pod, at a fixed count, so a render starts on a
#                      node that already exists.
#
# A render pod has no service account token and no cloud identity: the API
# reads the result over DevTools and stores it itself, so nothing here grants
# storage access.

locals {
  render_node_pool_name = "renders"

  render_node_pool_values = {
    name        = local.render_node_pool_name
    idleTimeout = var.agent_node_idle_timeout
    nodeClassRef = {
      group = "eks.amazonaws.com"
      kind  = "NodeClass"
      name  = "default"
    }
  }

  # The API's chart values (main.tf). An older chart ignores the key.
  render_chart_values = {
    enabled    = true
    namespace  = kubernetes_namespace_v1.renders.metadata[0].name
    secretName = aws_secretsmanager_secret.render.name
    nodePool   = local.render_node_pool_name
    warmPool = {
      enabled = var.render_warm_spares > 0
      spares  = var.render_warm_spares
    }
  }
}

resource "kubernetes_namespace_v1" "renders" {
  metadata {
    name = "renders"
  }
}

resource "helm_release" "render_node_pool" {
  name      = "render-node-pool"
  chart     = "${path.module}/../agent-node-pool"
  namespace = "kube-system"

  values = [yamlencode(local.render_node_pool_values)]

  wait            = true
  atomic          = true
  cleanup_on_fail = true

  lifecycle {
    precondition {
      condition     = length(module.cluster.node_pools) > 0
      error_message = "The renders NodePool needs the EKS default NodeClass, which exists only while a built-in NodePool is enabled."
    }
  }

  depends_on = [module.cluster]
}

# Generated here, not by hand: nothing outside the API needs the value, and
# replacing it only voids render links already issued, which expire in ten
# minutes.
resource "random_password" "render_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "render" {
  name = "${var.name}/api-render"
  tags = local.tags
}

# The chart's ExternalSecret reads RENDER_SECRET out of this JSON, so the shape
# is part of the contract.
resource "aws_secretsmanager_secret_version" "render" {
  secret_id     = aws_secretsmanager_secret.render.id
  secret_string = jsonencode({ RENDER_SECRET = random_password.render_secret.result })
}
