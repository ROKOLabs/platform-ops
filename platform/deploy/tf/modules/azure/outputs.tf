output "cluster_name" {
  value = module.implementation.cluster_name
}

output "cluster_endpoint" {
  value     = module.implementation.cluster_endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = module.implementation.cluster_ca_certificate
  sensitive = true
}

output "cluster_client_certificate" {
  value     = module.implementation.cluster_client_certificate
  sensitive = true
}

output "cluster_client_key" {
  value     = module.implementation.cluster_client_key
  sensitive = true
}

output "resource_group_name" {
  value = module.implementation.resource_group_name
}

output "db_host" {
  value = module.implementation.db_host
}

output "uploads_bucket" {
  value = module.implementation.uploads_bucket
}

output "checkpoints_bucket" {
  value = module.implementation.checkpoints_bucket
}

output "aks_control_plane_principal_id" {
  value = module.implementation.aks_control_plane_principal_id
}

output "required_role_assignments" {
  value = module.implementation.required_role_assignments
}

output "tickets_identity_client_id" {
  value = module.implementation.tickets_identity_client_id
}

output "tickets_identity_principal_id" {
  value = module.implementation.tickets_identity_principal_id
}

output "hostname" {
  value = module.implementation.hostname
}

output "ingress_hostname" {
  value = module.implementation.ingress_hostname
}

output "tls_secret_id" {
  value = module.implementation.tls_secret_id
}

output "origin_allowed_cidrs" {
  value = module.implementation.origin_allowed_cidrs
}

output "root_token" {
  value     = module.implementation.root_token
  sensitive = true
}

output "platform_version" {
  value = module.implementation.platform_version
}

output "acr_login_server" {
  value = module.implementation.acr_login_server
}

output "foundry_openai_endpoint" {
  value = module.implementation.foundry_openai_endpoint
}

output "foundry_account_id" {
  value = module.implementation.foundry_account_id
}

output "foundry_gpt_deployment_name" {
  value = module.implementation.foundry_gpt_deployment_name
}

output "telemetry_otlp_endpoint" {
  value = module.implementation.telemetry_otlp_endpoint
}

output "telemetry_headers_secret" {
  value = module.implementation.telemetry_headers_secret
}
