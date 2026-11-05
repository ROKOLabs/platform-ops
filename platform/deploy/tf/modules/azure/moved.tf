# Preserve all existing client state addresses when introducing the wrapper.
moved {
  from = azurerm_key_vault_secret.root_token
  to   = module.implementation.azurerm_key_vault_secret.root_token
}
moved {
  from = azurerm_key_vault_secret.secret_encryption
  to   = module.implementation.azurerm_key_vault_secret.secret_encryption
}
moved {
  from = azurerm_key_vault_secret.telemetry_headers
  to   = module.implementation.azurerm_key_vault_secret.telemetry_headers
}
moved {
  from = azurerm_resource_group.this
  to   = module.implementation.azurerm_resource_group.this
}
moved {
  from = azurerm_role_assignment.kubelet_acr_pull
  to   = module.implementation.azurerm_role_assignment.kubelet_acr_pull
}
moved {
  from = helm_release.agent_node_pool
  to   = module.implementation.helm_release.agent_node_pool
}
moved {
  from = helm_release.ingress_nginx
  to   = module.implementation.helm_release.ingress_nginx
}
moved {
  from = helm_release.platform
  to   = module.implementation.helm_release.platform
}
moved {
  from = kubernetes_secret_v1.origin_tls
  to   = module.implementation.kubernetes_secret_v1.origin_tls
}
moved {
  from = module.acr
  to   = module.implementation.module.acr
}
moved {
  from = module.aks
  to   = module.implementation.module.aks
}
moved {
  from = module.cluster_config
  to   = module.implementation.module.cluster_config
}
moved {
  from = module.foundry
  to   = module.implementation.module.foundry
}
moved {
  from = module.keyvault
  to   = module.implementation.module.keyvault
}
moved {
  from = module.postgres
  to   = module.implementation.module.postgres
}
moved {
  from = module.storage
  to   = module.implementation.module.storage
}
moved {
  from = module.telemetry
  to   = module.implementation.module.telemetry
}
moved {
  from = module.vnet
  to   = module.implementation.module.vnet
}
moved {
  from = module.workload_identity
  to   = module.implementation.module.workload_identity
}
moved {
  from = random_bytes.secret_encryption_key
  to   = module.implementation.random_bytes.secret_encryption_key
}
moved {
  from = random_password.root_token
  to   = module.implementation.random_password.root_token
}
moved {
  from = tls_private_key.origin
  to   = module.implementation.tls_private_key.origin
}
moved {
  from = tls_self_signed_cert.origin
  to   = module.implementation.tls_self_signed_cert.origin
}
