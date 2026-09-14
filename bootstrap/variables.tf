variable "prefix" {
  description = "Prefixo curto usado em todos os nomes de recursos deste projeto."
  type        = string
  default     = "azpe" # Azure Platform Engineering
}

variable "location" {
  description = "Região Azure onde o backend de estado e os recursos do projeto vivem."
  type        = string
  default     = "eastus2"
}

variable "github_repository" {
  description = "Repositório GitHub no formato 'owner/repo' que terá permissão de assumir a identidade via OIDC."
  type        = string
  default     = "pmacoy/azure-platform-engineering"
}

variable "github_environment" {
  description = "Nome do GitHub Environment usado para o job de apply gated (precisa bater com o workflow e com o Environment criado nas configurações do repositório)."
  type        = string
  default     = "production"
}

variable "allow_shared_access_key_bootstrap" {
  description = <<-EOT
    Controla shared_access_key_enabled no storage account de estado, só
    durante o bootstrap. FASE 1 (já concluída neste projeto): "true" --
    o storage account nasceu com a chave habilitada, então a checagem de
    disponibilidade do provider passou por chave, sem precisar de nenhuma
    role já propagada. FASE 2 (agora): "false" -- as roles Storage Blob
    Data Contributor e Storage Queue Data Reader já existem e já
    propagaram, então isto é só um update na chave (não uma recriação), e
    o ping de disponibilidade não é refeito.
  EOT
  type        = bool
  default     = false
}
