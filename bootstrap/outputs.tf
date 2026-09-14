output "state_resource_group_name" {
  description = "Nome do resource group do backend de estado -- vira TF_STATE_RG nos GitHub Secrets."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  description = "Nome do storage account do backend de estado -- vira TF_STATE_SA nos GitHub Secrets."
  value       = azurerm_storage_account.state.name
}

output "state_container_name" {
  description = "Nome do container de blobs usado pelo backend -- sempre 'tfstate'."
  value       = azurerm_storage_container.tfstate.name
}

output "azure_client_id" {
  description = "Client ID (application ID) da identidade OIDC -- vira AZURE_CLIENT_ID nos GitHub Secrets."
  value       = azuread_application.github_actions.client_id
}

output "azure_tenant_id" {
  description = "Tenant ID -- vira AZURE_TENANT_ID nos GitHub Secrets."
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "Subscription ID -- vira AZURE_SUBSCRIPTION_ID nos GitHub Secrets."
  value       = data.azurerm_client_config.current.subscription_id
}
