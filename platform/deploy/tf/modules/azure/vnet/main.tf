# The AKS subnet carries the pods, because Azure CNI gives every pod a VNet IP,
# so it takes half the range. The delegated Postgres subnet holds one server and
# sits at the top, leaving the middle free to grow into. Both were fixed
# 10.180.x values until now, which silently placed them outside any VNet given a
# different address space.
locals {
  aks_subnet_prefix      = var.aks_subnet_prefix != "" ? var.aks_subnet_prefix : cidrsubnet(var.address_space, 1, 0)
  postgres_subnet_prefix = var.postgres_subnet_prefix != "" ? var.postgres_subnet_prefix : cidrsubnet(var.address_space, 4, 15)
}

# VNet + two subnets — the Azure analog of modules/network (VPC + subnets).
# AKS uses Azure CNI, so pods get VNet IPs from the aks subnet; Postgres Flexible
# Server is VNet-injected into its own delegated subnet (private, no public IP).
resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.name}-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.aks_subnet_prefix]
}

# Flexible Server VNet integration requires a subnet delegated exclusively to it.
resource "azurerm_subnet" "postgres" {
  name                 = "${var.name}-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.postgres_subnet_prefix]

  delegation {
    name = "postgres-flexible-server"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
