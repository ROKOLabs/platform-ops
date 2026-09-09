output "cluster_name" { value = azurerm_kubernetes_cluster.this.name }
output "cluster_id" { value = azurerm_kubernetes_cluster.this.id }
output "agent_node_pool_id" { value = azurerm_kubernetes_cluster_node_pool.agents.id }

# OIDC issuer that federated identity credentials trust (see workload-identity).
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }

# The kubelet identity — grant it AcrPull so nodes can pull images.
output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }

# kube_config feeds the kubernetes/helm providers in the cluster-config stack.
output "kube_host" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive = true
}
output "kube_client_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
  sensitive = true
}
output "kube_client_key" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_key
  sensitive = true
}
output "kube_cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}
