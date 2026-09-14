output "resource_group_name" {
  description = "Nome do resource group da landing zone."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID da VNet -- consumido pela Fase 04 (AKS) para injetar o cluster na sub-rede privada."
  value       = azurerm_virtual_network.this.id
}

output "public_subnet_id" {
  description = "ID da sub-rede pública."
  value       = azurerm_subnet.public.id
}

output "private_subnet_id" {
  description = "ID da sub-rede privada -- é aqui que o AKS da Fase 04 vai viver."
  value       = azurerm_subnet.private.id
}

output "log_analytics_workspace_id" {
  description = "ID do workspace central de logs -- consumido pela Fase 06 (observabilidade) e pelo diagnóstico do AKS."
  value       = azurerm_log_analytics_workspace.this.id
}

output "key_vault_id" {
  description = "ID do Key Vault -- consumido pela Fase 06 (CSI driver de segredos no AKS)."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "URI do Key Vault."
  value       = azurerm_key_vault.this.vault_uri
}
