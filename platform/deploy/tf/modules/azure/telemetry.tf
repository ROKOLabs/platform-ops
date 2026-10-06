# ── Telemetry ────────────────────────────────────────────────────────────────
#
# The shared `../telemetry` collector, plus what only Azure has: Flexible Server
# host metrics from Azure Monitor, read by the gateway under its own workload
# identity (see ./workload-identity), and the Key Vault secret the export
# headers come from. `telemetry.enabled = false` removes every resource in this
# file, that identity, and the API's OTLP endpoint.

locals {
  telemetry_enabled         = var.telemetry.enabled
  telemetry_deployment_name = coalesce(var.telemetry.deployment_name, local.resource_prefix)

  # Merged into the API's chart values in main.tf.
  telemetry_api_values = {
    for k, v in { otel = { endpoint = one(module.telemetry[*].otlp_http_endpoint) } } : k => v
    if local.telemetry_enabled
  }

  # Azure Monitor metric names for the server, every five minutes.
  postgres_host_metrics = [
    "cpu_percent",
    "memory_percent",
    "storage_percent",
    "active_connections",
    "read_iops",
    "write_iops",
  ]
}

# The export header values, as JSON keyed by header name, for example
# {"api-key": "<ingest key>"}. Key Vault requires a value, so Terraform writes an
# empty object and then ignores the value; the operator sets it after the first
# apply. ESO reads it with the vault-wide grant of the external-secrets identity
# (see ./workload-identity).
resource "azurerm_key_vault_secret" "telemetry_headers" {
  count = local.telemetry_enabled ? 1 : 0

  name         = "telemetry-headers"
  key_vault_id = module.keyvault.vault_id
  value        = jsonencode({})

  lifecycle {
    ignore_changes = [value]
  }

  # The deployer's grant on the vault must exist and have propagated.
  depends_on = [module.keyvault]
}

module "telemetry" {
  source = "../telemetry"
  count  = local.telemetry_enabled ? 1 : 0

  namespace       = "telemetry"
  deployment_name = local.telemetry_deployment_name
  endpoint        = var.telemetry.endpoint
  protocol        = var.telemetry.protocol
  header_names    = var.telemetry.header_names

  # The same store the platform chart renders on Azure: workload identity with
  # no serviceAccountRef, so ESO reads with its controller's identity.
  headers_secret_key = azurerm_key_vault_secret.telemetry_headers[0].name
  secret_store_provider = {
    azurekv = { authType = "WorkloadIdentity", vaultUrl = module.keyvault.vault_uri }
  }

  # Flexible Server presents a certificate from a public root the collector
  # image trusts, so the server is verified.
  postgres = {
    host     = module.postgres.fqdn
    database = module.postgres.database_name
    username = module.postgres.administrator_login
    password = module.postgres.administrator_password
  }

  # The workload identity webhook projects a token into pods with this label
  # and sets AZURE_CLIENT_ID, AZURE_TENANT_ID and AZURE_FEDERATED_TOKEN_FILE from
  # the ServiceAccount annotation. `true` stays a string: label values are
  # strings.
  gateway_service_account_annotations = {
    "azure.workload.identity/client-id" = module.workload_identity.otel_gateway_client_id
  }
  gateway_pod_labels = { "azure.workload.identity/use" = "true" }

  gateway_extra_extensions = {
    azure_auth = {
      workload_identity = {
        client_id            = "$${env:AZURE_CLIENT_ID}"
        tenant_id            = "$${env:AZURE_TENANT_ID}"
        federated_token_file = "$${env:AZURE_FEDERATED_TOKEN_FILE}"
      }
    }
  }

  gateway_extra_receivers = {
    azuremonitor = {
      subscription_ids    = [data.azurerm_client_config.current.subscription_id]
      resource_groups     = [azurerm_resource_group.this.name]
      services            = ["Microsoft.DBforPostgreSQL/flexibleServers"]
      auth                = { authenticator = "azure_auth" }
      collection_interval = "300s"
      metrics = {
        "Microsoft.DBforPostgreSQL/flexibleServers" = { for metric in local.postgres_host_metrics : metric => ["Average"] }
      }
    }
  }

  # The pod should not start before its federated credential exists. The
  # gateway release renders a SecretStore and an ExternalSecret, so the ESO
  # CRDs must exist first.
  depends_on = [
    module.workload_identity,
    module.cluster_config,
  ]
}
