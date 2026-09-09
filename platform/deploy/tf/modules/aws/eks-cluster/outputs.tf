output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}
# Read the names carefully; they are one letter apart in meaning and the
# misleadingly-named one is almost never what a caller wants.
#
#   cluster_primary_security_group_id  the group EKS itself creates and attaches
#                                      to every node, so it is what a database or
#                                      a cache admits to let pods reach it.
#   cluster_security_group_id          the group this module creates for the
#                                      control plane. No node carries it.
output "cluster_primary_security_group_id" {
  description = "EKS-managed cluster security group, attached to every node. Allow this one to give pods access to something outside the cluster."
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "Control-plane security group created by this module. No node carries it; for pod access use cluster_primary_security_group_id."
  value       = module.eks.cluster_security_group_id
}
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
