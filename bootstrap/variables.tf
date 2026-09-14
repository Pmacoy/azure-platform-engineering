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
  description = "Repositório GitHub no formato 'owner/repo' que terá permissão de assumir a identidade via OIDC. Case-sensitive: precisa bater exatamente com o login registrado no GitHub."
  type        = string
  default     = "Pmacoy/azure-platform-engineering"
}

# Os dois IDs abaixo são numéricos e IMUTÁVEIS: o GitHub os embute no
# subject do token OIDC (veja o comentário do local.github_oidc_subject_prefix
# em main.tf). Onde achar esses números, se precisar conferir:
#
#   1. Na própria mensagem de erro AADSTS700213, que cita o subject
#      apresentado -- foi daí que estes vieram.
#   2. gh api repos/<owner>/<repo> --jq '{repo: .id, owner: .owner.id}'
#   3. https://api.github.com/repos/<owner>/<repo> no navegador (campos
#      "id" na raiz e "owner.id").
variable "github_owner_id" {
  description = "ID numérico imutável da conta/organização dona do repositório no GitHub."
  type        = string
  default     = "42946356"
}

variable "github_repository_id" {
  description = "ID numérico imutável do repositório no GitHub."
  type        = string
  default     = "1370531818"
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
