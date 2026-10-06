# ── Telemetry ────────────────────────────────────────────────────────────────
#
# The shared `../telemetry` collector, plus what only Azure has: Flexible Server
# host metrics from Azure Monitor, read by the gateway under its own workload
# identity (see ./workload-identity). `telemetry.enabled = false` removes every
# resource in this file, that identity, and the API's OTLP endpoint.

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

module "telemetry" {
  source = "../telemetry"
  count  = local.telemetry_enabled ? 1 : 0

  namespace       = "telemetry"
  deployment_name = local.telemetry_deployment_name
  endpoint        = var.telemetry.endpoint
  protocol        = var.telemetry.protocol
  headers         = var.telemetry_headers

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

  # The pod should not start before its federated credential exists.
  depends_on = [module.workload_identity]
}
