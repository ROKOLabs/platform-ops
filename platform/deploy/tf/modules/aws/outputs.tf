output "cluster_name" {
  description = "For `aws eks update-kubeconfig` and for CI."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Configures the deployment's own Kubernetes and Helm providers."
  value       = module.cluster.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA, for the same two providers."
  value       = module.cluster.cluster_certificate_authority_data
  sensitive   = true
}

output "db_host" {
  description = "Postgres endpoint."
  value       = aws_db_instance.platform.address
}

output "uploads_bucket" {
  description = "Object storage the Artifacts and Prototypes features use."
  value       = aws_s3_bucket.uploads.bucket
}

output "checkpoints_bucket" {
  description = "Object storage the agent supervisor writes run checkpoints to."
  value       = aws_s3_bucket.checkpoints.bucket
}

output "hostname" {
  description = "The name this deployment serves, echoed back, so Ops knows the record to create."
  value       = var.ingress_host
}

output "ingress_hostname" {
  description = "Load balancer address Roko points its proxied Cloudflare record at. Null until the chart's Ingress has been given one."
  value       = try(data.kubernetes_ingress_v1.platform.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "tls_secret_id" {
  description = "The ACM certificate the load balancer serves. Null unless `tls_mode` is `provided`, where the deployment supplies it."
  value       = var.tls_mode == "provided" ? var.tls_certificate_arn : null
}

output "origin_allowed_cidrs" {
  description = "Cloudflare ranges this apply allowed, so drift from what Cloudflare publishes now is visible in a plan."
  value = {
    ipv4 = local.origin_ipv4_cidrs
    ipv6 = local.origin_ipv6_cidrs
  }
}

output "platform_version" {
  description = "The release this module deploys, so a deployment can assert what it is running."
  value       = local.platform_version
}

output "api_ecr_repository_url" {
  description = "Registry a lane that builds its own API image pushes to."
  value       = module.api_ecr.repository_url
}

output "web_ecr_repository_url" {
  description = "Registry a lane that builds its own web image pushes to."
  value       = module.web_ecr.repository_url
}

output "agent_ecr_repository_url" {
  description = "Registry a lane that builds its own agent image pushes to."
  value       = module.agent_ecr.repository_url
}

# The load balancer is created by the chart's Ingress, not by Terraform, so its
# address is read back out of the cluster once Helm has applied. `try` above
# covers the window between the release completing and the controller filling in
# the status, where the field is genuinely absent rather than merely unknown.
data "kubernetes_ingress_v1" "platform" {
  metadata {
    name      = "roko-platform"
    namespace = kubernetes_namespace_v1.service.metadata[0].name
  }

  depends_on = [helm_release.platform]
}
