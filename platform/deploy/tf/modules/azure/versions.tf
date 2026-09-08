terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi      = { source = "Azure/azapi", version = "~> 2.0" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
    http       = { source = "hashicorp/http", version = "~> 3.4" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}
