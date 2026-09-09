output "account_id" { value = azapi_resource.account.id }
output "account_name" { value = azapi_resource.account.name }
output "anthropic_endpoint" { value = "https://${azapi_resource.account.name}.services.ai.azure.com/anthropic" }
output "project_name" { value = azapi_resource.project.name }
output "deployment_name" { value = one(azapi_resource.claude_sonnet_5[*].name) }
output "gpt_deployment_name" { value = one(azurerm_cognitive_deployment.gpt[*].name) }

# Paste this into the platform's model-provider form. The azure-openai kind
# requires an Azure AI host and the path /openai/v1/responses exactly.
output "openai_endpoint" { value = "https://${azapi_resource.account.name}.services.ai.azure.com/openai/v1/responses" }
