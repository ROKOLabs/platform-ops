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
  description = "Load balancer address Roko points its proxied Cloudflare record at. The apply waits for it, so it is never empty on a successful apply."
  value       = data.aws_lb.platform.dns_name
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

# The load balancer is created by the chart's Ingress, not by Terraform, and Helm
# does not wait for an Ingress: `wait` covers Deployments, Pods and
# LoadBalancer Services, and returns as soon as the pods are ready, which is
# minutes before the controller has finished provisioning the ALB. So a bare
# lookup here would fail the apply, and the address would be missing from the
# outputs the DNS record is created from.
#
# This polls for it with the same `aws` CLI the Kubernetes provider already
# needs, then reads it. The tags are what EKS Auto Mode's controller stamps on
# every load balancer it creates for an Ingress.
resource "terraform_data" "wait_for_load_balancer" {
  triggers_replace = [helm_release.platform.id]

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set -eu
      for attempt in $(seq 1 60); do
        found=$(aws resourcegroupstaggingapi get-resources           --region '${var.region}'           --resource-type-filters elasticloadbalancing:loadbalancer           --tag-filters 'Key=eks:eks-cluster-name,Values=${module.cluster.cluster_name}'                         'Key=ingress.eks.amazonaws.com/stack,Values=${kubernetes_namespace_v1.service.metadata[0].name}/roko-platform'           --query 'length(ResourceTagMappingList)' --output text)
        if [ "$found" -gt 0 ]; then
          echo "Load balancer ready after $attempt attempt(s)."
          exit 0
        fi
        sleep 10
      done
      echo "The load balancer did not appear within 10 minutes. Check the roko-platform Ingress in the service namespace." >&2
      exit 1
    EOT
  }
}

data "aws_lb" "platform" {
  tags = {
    "eks:eks-cluster-name"               = module.cluster.cluster_name
    "ingress.eks.amazonaws.com/stack"    = "${kubernetes_namespace_v1.service.metadata[0].name}/roko-platform"
    "ingress.eks.amazonaws.com/resource" = "LoadBalancer"
  }

  depends_on = [terraform_data.wait_for_load_balancer]
}
