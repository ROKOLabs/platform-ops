output "cluster_name" {
  description = "For `az aks get-credentials` and for CI."
  value       = module.aks.cluster_name
}

output "cluster_endpoint" {
  description = "Configures the deployment's own Kubernetes and Helm providers."
  value       = module.aks.kube_host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA, for the same two providers."
  value       = module.aks.kube_cluster_ca_certificate
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource group holding the deployment."
  value       = azurerm_resource_group.this.name
}

output "db_host" {
  description = "Postgres endpoint. The pod reads the whole URL from Key Vault; this is for a person connecting by hand."
  value       = module.postgres.fqdn
}

output "uploads_bucket" {
  description = "Blob container the Artifacts and Prototypes features use."
  value       = module.storage.container_name
}

output "checkpoints_bucket" {
  description = "Blob container the agent supervisor writes run checkpoints to."
  value       = module.storage.checkpoints_container_name
}

output "hostname" {
  description = "The name this deployment serves, echoed back, so Ops knows the record to create."
  value       = var.ingress_host
}

output "ingress_hostname" {
  description = "Load balancer address Roko points its proxied Cloudflare record at. On Azure it is a static IP, so the record is an A. Null until the controller's Service has been given one."
  value       = try(data.kubernetes_service_v1.ingress_nginx.status[0].load_balancer[0].ingress[0].ip, null)
}

output "tls_secret_id" {
  description = "The Secret to drop a certificate into. Null unless `tls_mode` is `provided`."
  value       = var.tls_mode == "provided" ? kubernetes_secret_v1.origin_tls.metadata[0].name : null
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

output "acr_login_server" {
  description = "Registry a lane that builds its own images pushes to."
  value       = module.acr.login_server
}

output "foundry_openai_endpoint" {
  description = "Endpoint a person pastes into Settings, Models, beside an account API key."
  value       = module.foundry.openai_endpoint
}

output "foundry_gpt_deployment_name" {
  description = "Deployment name that goes into the same form."
  value       = module.foundry.gpt_deployment_name
}

# The address belongs to the controller's Service, which Helm created, so it is
# read back out of the cluster after the release.
data "kubernetes_service_v1" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.ingress_nginx.namespace
  }

  depends_on = [helm_release.ingress_nginx]
}
