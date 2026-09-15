variable "name" {
  description = "Nome base da identidade (ex: 'azpe-dev-backstage'). Vira o prefixo dos recursos criados."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group onde a identidade gerenciada é criada."
  type        = string
}

variable "location" {
  description = "Região Azure da identidade gerenciada."
  type        = string
}

variable "oidc_issuer_url" {
  description = "URL do emissor OIDC do cluster AKS (output oidc_issuer_url do módulo aks)."
  type        = string
}

variable "namespace" {
  description = "Namespace do Kubernetes onde o pod roda. Faz parte do subject do token -- precisa bater exatamente."
  type        = string
}

variable "service_account_name" {
  description = "Nome da ServiceAccount que o pod usa. Faz parte do subject do token -- precisa bater exatamente."
  type        = string
}

variable "key_vault_id" {
  description = "ID do Key Vault de onde esta identidade pode LER segredos."
  type        = string
}

variable "tags" {
  description = "Tags aplicadas aos recursos deste módulo."
  type        = map(string)
  default     = {}
}
