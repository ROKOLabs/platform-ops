# Plan-only tests of the telemetry wiring, with every provider mocked. Run from
# modules/azure:
#
#   terraform init -backend=false && terraform test
#
# The azurerm provider parses resource IDs even under a mock, so the child
# modules that only feed IDs into the telemetry wiring are replaced by their
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

run "disabled_creates_no_telemetry" {
  command = plan

  variables {
    telemetry = { enabled = false }
  }

  assert {
    condition     = length(module.telemetry) == 0
    error_message = "telemetry.enabled = false must not create the telemetry module."
  }

  assert {
    condition     = module.workload_identity.otel_gateway_client_id == null
    error_message = "telemetry.enabled = false must not create the otel-gateway identity."
  }

  assert {
    condition     = length(azurerm_key_vault_secret.telemetry_headers) == 0
    error_message = "telemetry.enabled = false must not create the headers secret."
  }

  assert {
    condition     = !contains(keys(local.platform_values.api), "otel")
    error_message = "telemetry.enabled = false must not set api.otel."
  }

  assert {
    condition     = !contains(keys(local.platform_values.web), "otel")
    error_message = "telemetry.enabled = false must not set web.otel."
  }

  assert {
    condition     = output.telemetry_otlp_endpoint == null && output.telemetry_headers_secret == null
    error_message = "The telemetry outputs must be null when telemetry is disabled."
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = keys(module.telemetry[0].gateway_config.exporters) == ["otlphttp"]
    error_message = "The default protocol must use the otlphttp exporter."
  }

  assert {
    condition     = module.telemetry[0].gateway_config.exporters.otlphttp.endpoint == "https://otlp.rokolabs.ai"
    error_message = "The default endpoint must be https://otlp.rokolabs.ai."
  }

  assert {
    condition     = module.telemetry[0].gateway_config.exporters.otlphttp.headers == { "api-key" = "$${env:OTLP_HEADER_0}" }
    error_message = "The default header api-key must be bound to OTLP_HEADER_0."
  }

  assert {
    condition     = azurerm_key_vault_secret.telemetry_headers[0].name == "telemetry-headers" && azurerm_key_vault_secret.telemetry_headers[0].value == "{}"
    error_message = "The headers secret must be telemetry-headers with an empty JSON object as its placeholder."
  }

  assert {
    condition     = output.telemetry_headers_secret == { vault_name = "acme-test-kv", secret_name = "telemetry-headers" }
    error_message = "telemetry_headers_secret must name the vault and the secret."
  }

  assert {
    condition     = module.telemetry[0].gateway_manifests[0].spec.provider.azurekv == { authType = "WorkloadIdentity", vaultUrl = "https://acme-test-kv.vault.azure.net/" }
    error_message = "The SecretStore must read the vault with workload identity."
  }

  assert {
    condition = module.telemetry[0].gateway_manifests[1].spec.data == [
      { secretKey = "OTLP_HEADER_0", remoteRef = { key = "telemetry-headers", property = "api-key" } },
    ]
    error_message = "The ExternalSecret must map property api-key of the headers secret to OTLP_HEADER_0."
  }

  assert {
    condition     = contains(module.telemetry[0].gateway_config.service.pipelines.metrics.receivers, "azuremonitor")
    error_message = "The gateway must read the Postgres host metrics from Azure Monitor."
  }

  assert {
    condition     = module.workload_identity.otel_gateway_client_id == "11111111-1111-1111-1111-111111111111"
    error_message = "The gateway must get its own workload identity."
  }

  assert {
    condition     = local.platform_values.api.otel.endpoint == "http://otel-gateway.telemetry.svc.cluster.local:4318"
    error_message = "api.otel.endpoint must point at the gateway when telemetry is enabled."
  }

  assert {
    condition     = local.platform_values.web.otel.endpoint == "http://otel-gateway.telemetry.svc.cluster.local:4318"
    error_message = "web.otel.endpoint must point at the gateway when telemetry is enabled."
  }

  assert {
    condition     = module.telemetry[0].gateway_config.service.pipelines.traces.processors == ["memory_limiter", "k8sattributes", "resource", "resource/trim", "tail_sampling", "batch"]
    error_message = "Traces must be trimmed and tail-sampled before they are batched."
  }

  assert {
    condition     = [for p in module.telemetry[0].gateway_config.processors.tail_sampling.policies : p.name] == ["errors", "slow", "sample"]
    error_message = "Tail sampling must keep errors and slow traces, and sample the rest."
  }

  assert {
    condition     = module.telemetry[0].gateway_config.service.pipelines["traces/span_metrics"].exporters == ["span_metrics"] && module.telemetry[0].gateway_config.service.pipelines["metrics/span_metrics"].receivers == ["span_metrics"]
    error_message = "Span metrics must be derived from unsampled traces and exported as metrics."
  }

  assert {
    condition     = module.telemetry[0].gateway_config.receivers.postgresql.collection_interval == "300s" && !module.telemetry[0].gateway_config.receivers.postgresql.metrics["postgresql.blocks_read"].enabled
    error_message = "Postgres statistics must be read every 5 minutes without blocks_read."
  }
}

run "grpc_with_two_headers" {
  command = plan

  variables {
    telemetry = {
      endpoint     = "https://otlp.example.com:4317"
      protocol     = "grpc"
      header_names = ["a", "b"]
    }
  }

  assert {
    condition     = keys(module.telemetry[0].gateway_config.exporters) == ["otlp"]
    error_message = "protocol = grpc must use the otlp exporter."
  }

  assert {
    condition = module.telemetry[0].gateway_config.exporters.otlp.headers == {
      a = "$${env:OTLP_HEADER_0}"
      b = "$${env:OTLP_HEADER_1}"
    }
    error_message = "Each header must be bound to its own OTLP_HEADER_<i> environment variable."
  }

  assert {
    condition = module.telemetry[0].gateway_manifests[1].spec.data == [
      { secretKey = "OTLP_HEADER_0", remoteRef = { key = "telemetry-headers", property = "a" } },
      { secretKey = "OTLP_HEADER_1", remoteRef = { key = "telemetry-headers", property = "b" } },
    ]
    error_message = "The ExternalSecret must map both properties."
  }
}

run "invalid_endpoint_fails" {
  command = plan

  variables {
    telemetry = { endpoint = "otlp.example.com" }
  }

  expect_failures = [var.telemetry]
}
