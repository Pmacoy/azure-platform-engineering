data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# ---------------------------------------------------------------------------
# 1. Backend remoto do Terraform
#
# Um Storage Account com um container de blobs guarda o tfstate de tudo que
# vem depois (environments/dev). `shared_access_key_enabled = false` desliga
# a chave de acesso estática do storage account por completo -- a única
# forma de ler/escrever nele passa a ser identidade do Azure AD (a mesma
# ideia de "sem secret estático" que vamos aplicar no login do GitHub
# Actions logo abaixo). Versionamento de blob ligado dá um jeito barato de
# recuperar um tfstate corrompido sem precisar de backup separado.
# ---------------------------------------------------------------------------

resource "random_string" "state_sa_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "${var.prefix}-rg-tfstate"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                = "${var.prefix}sa${random_string.state_sa_suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # força autenticação via Azure AD, nunca chave estática

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id # provider v4: storage_account_id substitui storage_account_name aqui
  container_access_type = "private"
}

# O usuário/service principal que roda este bootstrap também precisa de
# permissão de dados no container que acabou de criar -- só ser "Owner" da
# assinatura não basta quando a chave estática está desligada.
resource "azurerm_role_assignment" "bootstrap_runner_state_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Blob e Queue são serviços de dados diferentes no Azure, com roles RBAC
# diferentes -- "Storage Blob Data Contributor" não dá acesso nenhum a
# Queue. O provider azurerm, ao ler o estado de QUALQUER
# azurerm_storage_account (mesmo um que só usamos para blobs), sempre
# confere as propriedades do serviço de Queue como parte do schema do
# recurso. Com shared_access_key_enabled = false, essa leitura também vai
# por Azure AD -- e sem esta role, ela recebe 403. Read-only porque é
# só isso que o refresh do Terraform precisa.
resource "azurerm_role_assignment" "bootstrap_runner_state_queue" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Queue Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# 2. Identidade OIDC para o GitHub Actions (sem secret estático)
#
# Em vez de gerar um client secret e colar ele nos GitHub Secrets (o que
# significa: um segredo de longa duração, guardado em texto, que alguém
# precisa lembrar de rotacionar), o GitHub Actions troca um token OIDC de
# curtíssima duração, emitido pelo próprio GitHub a cada execução, por um
# token de acesso do Azure AD -- só se a "federated identity credential"
# abaixo reconhecer exatamente aquele repositório e aquele contexto (branch,
# pull request, ou environment). Não existe segredo para vazar porque não
# existe segredo.
# ---------------------------------------------------------------------------

resource "azuread_application" "github_actions" {
  display_name = "${var.prefix}-github-actions-oidc"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# Credencial usada pelo job de "plan": confia em qualquer pull request
# aberta contra este repositório. Só dá plan -- nunca apply -- então o
# blast radius de confiar em "qualquer PR" é baixo por design.
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-pull-request"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:pull_request"
}

# Credencial usada pelo job de "apply": confia especificamente no GitHub
# Environment gated (com aprovação manual configurada no repositório), não
# na branch main em si. Assim, mesmo um push direto na main sem passar por
# PR não teria como disparar um apply sem alguém clicar "approve".
resource "azuread_application_federated_identity_credential" "gated_environment" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-environment-${var.github_environment}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repository}:environment:${var.github_environment}"
}

# ---------------------------------------------------------------------------
# 3. Permissões da identidade do GitHub Actions
#
# Contributor na assinatura inteira é deliberadamente amplo demais para uma
# plataforma madura -- é o ponto de partida realista de um projeto pessoal,
# não o estado final. Na Fase 05/M5 (guardrails), isso é exatamente o tipo
# de coisa que se aperta: escopo por resource group, Azure Policy negando
# categorias inteiras de recurso, PIM em vez de atribuição permanente.
# Documentar esse trade-off aqui é, em si, uma resposta de entrevista.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "github_actions_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_state_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
