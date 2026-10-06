output "otlp_http_endpoint" {
  description = "In-cluster OTLP/HTTP endpoint the platform's own services export to."
  value       = "http://${local.gateway_name}.${kubernetes_namespace_v1.this.metadata[0].name}.svc.cluster.local:4318"
}

output "namespace" {
  description = "Namespace the collectors run in."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "gateway_service_account" {
  description = "ServiceAccount of the gateway, which the cloud module binds its workload identity to."
  value       = local.gateway_name
}

output "gateway_files_volume" {
  description = "Volume name sidecars mount to read `gateway_extra_files`."
  value       = local.files_volume
}

output "gateway_config" {
  description = "Collector config the gateway is installed with, before the chart's presets add to it. Exposed for tests and for reading in a plan."
  value       = local.gateway_config
}

output "node_config" {
  description = "Collector config the node DaemonSet is installed with, before the chart's presets add to it."
  value       = local.node_config
}

output "gateway_manifests" {
  description = "SecretStore and ExternalSecret the gateway release renders. Exposed for tests."
  value       = local.gateway_manifests
}

output "headers_secret_name" {
  description = "Kubernetes Secret ESO writes the header values to."
  value       = local.headers_secret_name
}
