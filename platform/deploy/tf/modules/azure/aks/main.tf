# AKS — the Azure analog of modules/eks-cluster. Two things the platform depends
# on are turned on here: the OIDC issuer and Workload Identity, which together are
# the direct analog of EKS Pod Identity (federate a k8s ServiceAccount to a
# user-assigned managed identity — see modules/workload-identity). Azure CNI puts
# pods on the VNet, matching the EKS VPC-CNI model.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.aks_subnet_id
  }

  # System-assigned identity for the control plane; workloads use their own
  # user-assigned identities via Workload Identity, never this one.
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  # Only pin authorized ranges when the caller supplies them; an empty list means
  # the public API server stays open (the default, matching api_allowed_cidrs=[]).
  dynamic "api_server_access_profile" {
    for_each = length(var.api_allowed_cidrs) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_allowed_cidrs
    }
  }

  tags = var.tags
}

# EKS Auto Mode gives application pods a general-purpose pool whose capacity is
# separate from its system pool. AKS cluster autoscaling cannot choose a VM size
# per pod, so agent runs get an explicit user pool sized for their fixed request.
# The taint reserves this capacity for Jobs that opt in through the chart's
# agents.nodePool value.
resource "azurerm_kubernetes_cluster_node_pool" "agents" {
  name                  = "agents"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  orchestrator_version  = var.kubernetes_version
  vm_size               = var.agent_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  mode                  = "User"

  auto_scaling_enabled = true
  node_count           = var.agent_node_min_count
  min_count            = var.agent_node_min_count
  max_count            = var.agent_node_max_count

  node_labels = {
    "roko.dev/agent-pool" = "agents"
  }
  node_taints = ["roko.dev/agent-pool=agents:NoSchedule"]

  tags = merge(var.tags, { Workload = "agents" })

  lifecycle {
    ignore_changes = [node_count]

    precondition {
      condition     = var.agent_node_max_count >= var.agent_node_min_count
      error_message = "agent_node_max_count must be greater than or equal to agent_node_min_count."
    }
  }
}
