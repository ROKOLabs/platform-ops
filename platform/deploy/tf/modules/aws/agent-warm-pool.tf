# ── Agent nodes ──────────────────────────────────────────────────────────────
#
# Spare agent nodes kept warm between runs (Roko CR-379). Three parts:
#
#   agents NodePool   The dedicated Karpenter pool agent Jobs run on, from
#                     the local ../agent-node-pool chart. Agent pods select it
#                     through the platform chart's api.agents.nodePool value.
#   KEDA              Scales the platform chart's placeholder Deployment from
#                     the API's GET /internal/agent-pool. The chart renders the
#                     ScaledObject; this release provides the operator and its
#                     CRDs, so the platform release depends on it.
#   warmPool.enabled  Turns the placeholders on in the platform values.
#
# A helm_release of a local chart rather than kubernetes_manifest: this module
# creates the cluster in the same apply, and kubernetes_manifest needs the
# Karpenter CRD at plan time, so a fresh deployment would fail to plan.
#
# EKS Auto Mode provisions the `default` NodeClass the pool references only
# while a built-in NodePool is enabled. The precondition fails the plan before
# a pool that could launch nothing is created.

locals {
  agent_node_pool_name = "agents"

  agent_node_pool_values = {
    name        = local.agent_node_pool_name
    idleTimeout = var.agent_node_idle_timeout
    cpuLimit    = var.agent_node_pool_cpu_limit
    nodeClassRef = {
      group = "eks.amazonaws.com"
      kind  = "NodeClass"
      name  = "default"
    }
  }

  # Merged into the API's chart values in main.tf.
  agent_warm_pool_chart_values = {
    nodePool = local.agent_node_pool_name
    warmPool = { enabled = true }
  }
}

resource "helm_release" "agent_node_pool" {
  name      = "agent-node-pool"
  chart     = "${path.module}/../agent-node-pool"
  namespace = "kube-system"

  values = [yamlencode(local.agent_node_pool_values)]

  wait            = true
  atomic          = true
  cleanup_on_fail = true

  lifecycle {
    precondition {
      condition     = length(module.cluster.node_pools) > 0
      error_message = "The agents NodePool needs the EKS default NodeClass, which exists only while a built-in NodePool is enabled."
    }
  }

  depends_on = [module.cluster]
}

resource "kubernetes_namespace_v1" "keda" {
  metadata {
    name = "keda"
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_chart_version
  namespace  = kubernetes_namespace_v1.keda.metadata[0].name

  timeout         = 600
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  depends_on = [module.cluster]
}
