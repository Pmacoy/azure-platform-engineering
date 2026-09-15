output "resource_group_name" {
  value = module.landing_zone.resource_group_name
}

output "vnet_id" {
  value = module.landing_zone.vnet_id
}

output "private_subnet_id" {
  value = module.landing_zone.private_subnet_id
}

output "log_analytics_workspace_id" {
  value = module.landing_zone.log_analytics_workspace_id
}

output "key_vault_uri" {
  value = module.landing_zone.key_vault_uri
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_node_resource_group" {
  description = "Resource group gerenciado pelo AKS -- onde as VMs e discos cobrados aparecem."
  value       = module.aks.node_resource_group
}

output "acr_login_server" {
  value = module.aks.acr_login_server
}

output "key_vault_name" {
  description = "Nome do Key Vault -- usado no SecretProviderClass e no `az keyvault secret set`."
  value       = element(split("/", module.landing_zone.key_vault_id), length(split("/", module.landing_zone.key_vault_id)) - 1)
}

output "backstage_identity_client_id" {
  description = "Client ID que vai na anotação azure.workload.identity/client-id da ServiceAccount do Backstage."
  value       = module.backstage_identity.client_id
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
