# AKS uses a fixed system pool for critical add-ons and NAP for application
# pods, like the system and general-purpose pools in EKS Auto Mode. The cluster
# identity needs subnet access before AKS creates NAP nodes in this custom VNet.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "control_plane_subnet" {
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
    name                         = "system"
    node_count                   = var.node_count
    vm_size                      = var.node_vm_size
    vnet_subnet_id               = var.aks_subnet_id
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    # A zone is where compute comes from as well as where redundancy lives. In a
    # region whose capacity is tight, asking across three zones is often the
    # difference between a node being created and a pod staying Pending.
    zones = var.zones
  }

  # The control-plane identity is separate from pod Workload Identities. Using
  # a pre-created identity lets one apply grant subnet access before AKS starts.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  node_provisioning_profile {
    mode               = "Auto"
    default_node_pools = "Auto"
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
