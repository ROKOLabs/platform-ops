# Client ids surface as chart values: workloadIdentity.clientId (roko-api) and
# the external-secrets SA annotation set in the cluster-config module.
output "api_client_id" { value = azurerm_user_assigned_identity.api.client_id }
output "external_secrets_client_id" { value = azurerm_user_assigned_identity.external_secrets.client_id }
