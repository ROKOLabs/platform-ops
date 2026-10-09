# Plan-only tests of the agent warm pool wiring (Roko CR-379), with every provider mocked. Run from
# modules/azure:
#
#   terraform init -backend=false && terraform test
#
# The azurerm provider parses resource IDs even under a mock, so the child
# modules that only feed IDs into the agent warm pool wiring are replaced by their
# outputs. workload-identity stays real: it holds the telemetry identity.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    override_during = plan
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
      client_id    = "11111111-1111-1111-1111-111111111111"
      principal_id = "22222222-2222-2222-2222-222222222222"
    }
  }
}

mock_provider "azapi" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "http" {}

override_module {
  target = module.vnet
  outputs = {
    vnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.Network/virtualNetworks/acme-test"
    aks_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.Network/virtualNetworks/acme-test/subnets/aks"
    postgres_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.Network/virtualNetworks/acme-test/subnets/postgres"
  }
}

override_module {
  target = module.aks
  outputs = {
    cluster_name                = "acme-test"
    oidc_issuer_url             = "https://oidc.example.com/"
    kubelet_identity_object_id  = "33333333-3333-3333-3333-333333333333"
    kube_host                   = "https://aks.example.com"
    kube_client_certificate     = ""
    kube_client_key             = ""
    kube_cluster_ca_certificate = ""
  }
}

override_module {
  target = module.storage
  outputs = {
    account_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.Storage/storageAccounts/acmetestuploads"
    account_name               = "acmetestuploads"
    container_name             = "uploads"
    checkpoints_container_name = "agent-checkpoints"
  }
}

override_module {
  target = module.acr
  outputs = {
    registry_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.ContainerRegistry/registries/acmetestacr"
    login_server = "acmetestacr.azurecr.io"
  }
}

override_module {
  target = module.keyvault
  outputs = {
    vault_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.KeyVault/vaults/acme-test-kv"
    vault_uri  = "https://acme-test-kv.vault.azure.net/"
    vault_name = "acme-test-kv"
  }
}

override_module {
  target = module.postgres
  outputs = {
    server_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/acme-test-pg"
    fqdn                     = "acme-test-pg.postgres.database.azure.com"
    database_name            = "platform"
    database_url_secret_name = "database-url"
    administrator_login      = "roko"
    administrator_password   = "password"
  }
}

override_module {
  target = module.foundry
  outputs = {
    account_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/acme-test/providers/Microsoft.CognitiveServices/accounts/acme-test-foundry"
    openai_endpoint     = "https://acme-test-foundry.openai.azure.com/"
    gpt_deployment_name = "gpt-5.4-mini"
  }
}

override_module {
  target = module.cluster_config
  outputs = {
    service_namespace          = "service"
    external_secrets_namespace = "external-secrets"
  }
}

variables {
  name                          = "acme-test"
  location                      = "southcentralus"
  ingress_host                  = "acme.example.com"
  api_allowed_cidrs             = ["203.0.113.0/24"]
  storage_account_name          = "acmetestuploads"
  acr_name                      = "acmetestacr"
  key_vault_name                = "acme-test-kv"
  postgres_server_name          = "acme-test-pg"
  restrict_origin_to_cloudflare = false
  foundry = {
    account_name = "acme-test-foundry"
    project_name = "acme-test"
  }
}

run "nap" {
  command = plan

  assert {
    condition     = length(helm_release.agent_node_pool) == 1
    error_message = "The NAP shape must create the agents NodePool."
  }

  assert {
    condition     = yamldecode(helm_release.agent_node_pool[0].values[0]) == { name = "agents", idleTimeout = "30s", nodeClassRef = { group = "karpenter.azure.com", kind = "AKSNodeClass", name = "default" } }
    error_message = "The agents NodePool must consolidate after 30s, set no limits and reference the AKSNodeClass default."
  }

  assert {
    condition     = local.platform_values.api.agents.nodePool == "agents"
    error_message = "api.agents.nodePool must select the agents NodePool."
  }

  assert {
    condition     = local.platform_values.api.agents.warmPool.enabled == true
    error_message = "api.agents.warmPool.enabled must be true under NAP, where the KEDA add-on runs."
  }
}

run "nap_node_class_override" {
  command = plan

  variables {
    agent_node_class_name = "agents"
  }

  assert {
    condition     = yamldecode(helm_release.agent_node_pool[0].values[0]).nodeClassRef.name == "agents"
    error_message = "agent_node_class_name must name the AKSNodeClass the pool references."
  }
}

run "without_nap" {
  command = plan

  variables {
    roles_granted_by_client = []
  }

  assert {
    condition     = length(helm_release.agent_node_pool) == 0
    error_message = "Without NAP there is no Karpenter, so no agents NodePool release."
  }

  assert {
    condition     = local.platform_values.api.agents.warmPool.enabled == false
    error_message = "api.agents.warmPool.enabled must be false without the KEDA add-on."
  }

  assert {
    condition     = local.platform_values.api.agents.nodePool == "agents"
    error_message = "api.agents.nodePool must still name the fixed agents pool."
  }
}
