output "cluster_name" {
  description = "Nome do cluster AKS -- usado no `az aks get-credentials` e pelo Argo CD do M3."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "ID completo do cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "node_resource_group" {
  description = "Resource group gerenciado pelo AKS onde vivem as VMs, discos e o load balancer -- é aqui que o custo aparece na fatura."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "acr_name" {
  description = "Nome do Container Registry."
  value       = azurerm_container_registry.this.name
}

output "acr_login_server" {
  description = "Endereço do registry (ex: azpedevacrab12cd.azurecr.io) -- é o prefixo das tags de imagem no pipeline do M3."
  value       = azurerm_container_registry.this.login_server
}

# Deliberadamente NÃO exportamos kube_config nem kube_admin_config. Eles
# contêm credencial de acesso total ao cluster; exportar como output faz
# esse segredo aparecer em `terraform output` e no resumo de qualquer
# pipeline que rode isso. O caminho certo de acesso é
# `az aks get-credentials`, que emite credencial própria por usuário via
# Azure AD.
