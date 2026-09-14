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
