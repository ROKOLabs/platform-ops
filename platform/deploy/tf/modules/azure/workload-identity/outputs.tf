# Client ids surface as chart values: workloadIdentity.clientId and
# ticketing.azureDevOpsIdentityClientId for roko-api, plus the external-secrets
# SA annotation set in the cluster-config module.
output "api_client_id" { value = azurerm_user_assigned_identity.api.client_id }

# The principal a client that grants roles itself gives Foundry User on the
# Foundry account.
output "api_principal_id" { value = azurerm_user_assigned_identity.api.principal_id }
output "tickets_client_id" { value = azurerm_user_assigned_identity.tickets.client_id }
output "tickets_principal_id" { value = azurerm_user_assigned_identity.tickets.principal_id }
output "external_secrets_client_id" { value = azurerm_user_assigned_identity.external_secrets.client_id }
