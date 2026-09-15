output "client_id" {
  description = <<-EOT
    Client ID da identidade. É este valor que vai na anotação
    `azure.workload.identity/client-id` da ServiceAccount no Kubernetes --
    é como o pod diz ao webhook qual identidade ele quer assumir.
  EOT
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object ID da identidade (usado para conceder outras roles fora deste módulo)."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "name" {
  description = "Nome da identidade gerenciada criada."
  value       = azurerm_user_assigned_identity.this.name
}
