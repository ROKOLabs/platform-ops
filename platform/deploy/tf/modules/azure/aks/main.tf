# AKS uses a fixed system pool for critical add-ons and NAP for application
# pods, like the system and general-purpose pools in EKS Auto Mode. The cluster
# identity needs subnet access before AKS creates NAP nodes in this custom VNet.
#
# `roles_granted_by_client` decides who makes that grant. null: this module
# assigns Network Contributor itself. A set without "aks-subnet": the client
# has not granted it yet, so the cluster keeps the pre-NAP shape of
# system-assigned identity, fixed `agents` pool, and no NAP. A set with
# "aks-subnet": the client has granted, and the cluster takes the NAP shape
# without the assignment.
locals {
  manage_grants = var.roles_granted_by_client == null
  nap           = local.manage_grants || contains(var.roles_granted_by_client, "aks-subnet")
}

# The identity exists in every mode, so its name and every reference to it stay
# inside the module, and a client can grant on it before adding the key.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "control_plane_subnet" {
  count = local.manage_grants ? 1 : 0

  scope                            = var.aks_subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

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

    # Reserving the system pool for critical add-ons only works once NAP
    # provides application capacity, so before the subnet grant it stays open.
    only_critical_addons_enabled = local.nap
    temporary_name_for_rotation  = "systemtmp"
    # A zone is where compute comes from as well as where redundancy lives. In a
    # region whose capacity is tight, asking across three zones is often the
    # difference between a node being created and a pod staying Pending.
    zones = var.zones
  }

  # The control-plane identity is separate from pod Workload Identities. Using
  # a pre-created identity lets one apply grant subnet access before AKS starts.
  # Azure checks that access during the switch to UserAssigned, so the cluster
  # stays on the system-assigned identity until the grant exists.
  identity {
    type         = local.nap ? "UserAssigned" : "SystemAssigned"
    identity_ids = local.nap ? [azurerm_user_assigned_identity.control_plane.id] : null
  }

  dynamic "node_provisioning_profile" {
    for_each = local.nap ? [1] : []
    content {
      mode               = "Auto"
      default_node_pools = "Auto"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
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

  depends_on = [azurerm_role_assignment.control_plane_subnet]
}

# Before the subnet grant there is no NAP, so agent Jobs keep the fixed user
# pool they had before NAP: one three-CPU, 8Gi agent per D4s_v5 node, reserved
# by the taint for Jobs that opt in through the chart's agents.nodePool value.
# The sizing is fixed because this shape is transitional.
resource "azurerm_kubernetes_cluster_node_pool" "agents" {
  count = local.nap ? 0 : 1

  name                  = "agents"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  orchestrator_version  = var.kubernetes_version
  vm_size               = "Standard_D4s_v5"
  vnet_subnet_id        = var.aks_subnet_id
  mode                  = "User"

  auto_scaling_enabled = true
  node_count           = 1
  min_count            = 1
  max_count            = 3
  zones                = var.zones

  node_labels = {
    "roko.dev/agent-pool" = "agents"
  }
  node_taints = ["roko.dev/agent-pool=agents:NoSchedule"]

  tags = merge(var.tags, { Workload = "agents" })

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Releases before NAP created the pool without an index. Without this move, a
# client upgrading into the pre-NAP shape would destroy and recreate the pool.
moved {
  from = azurerm_kubernetes_cluster_node_pool.agents
  to   = azurerm_kubernetes_cluster_node_pool.agents[0]
}
