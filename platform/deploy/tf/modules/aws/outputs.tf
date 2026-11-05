output "cluster_name" {
  value = module.implementation.cluster_name
}

output "cluster_endpoint" {
  value = module.implementation.cluster_endpoint
}

output "cluster_ca_certificate" {
  value     = module.implementation.cluster_ca_certificate
  sensitive = true
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

output "api_ecr_repository_url" {
  value = module.implementation.api_ecr_repository_url
}

output "web_ecr_repository_url" {
  value = module.implementation.web_ecr_repository_url
}

output "agent_ecr_repository_url" {
  value = module.implementation.agent_ecr_repository_url
}

output "telemetry_otlp_endpoint" {
  value = module.implementation.telemetry_otlp_endpoint
}

output "telemetry_headers_secret" {
  value = module.implementation.telemetry_headers_secret
}

output "vpc_id" {
  value = module.implementation.vpc_id
}

output "private_subnet_ids" {
  value = module.implementation.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.implementation.public_subnet_ids
}

output "db_master_secret_arn" {
  value = module.implementation.db_master_secret_arn
}
