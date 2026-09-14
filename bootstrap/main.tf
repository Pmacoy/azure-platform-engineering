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

  # FASE 1 DE 2 -- veja a variável logo abaixo antes de mudar isto direto.
  # O provider, ao terminar de criar o storage account, faz um "ping" no
  # serviço de Blob pra confirmar que já está disponível. Com a chave
  # desligada, esse ping também exige uma identidade do Azure AD
  # autorizada -- mas a role que autoriza isso (mais abaixo neste arquivo)
  # só pode ser criada DEPOIS que o storage account existir, porque ela
  # referencia o ID dele. Ligar a chave só nesta primeira aplicação evita
  # esse ciclo: o ping passa por chave, a role se propaga, e depois
  # desligamos a chave de vez numa segunda aplicação (que é só um update,
  # não uma recriação -- não dispara esse ping de novo).
  shared_access_key_enabled = var.allow_shared_access_key_bootstrap

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

locals {
  github_owner     = split("/", var.github_repository)[0]
  github_repo_name = split("/", var.github_repository)[1]

  # O "subject" (claim `sub`) que o GitHub coloca no token OIDC NÃO é
  # simplesmente "repo:<owner>/<repo>". Ele embute os IDs numéricos
  # imutáveis da conta e do repositório:
  #
  #   repo:Pmacoy@42946356/azure-platform-engineering@1370531818:ref:refs/heads/main
  #
  # Por que o GitHub faz isso: nomes de conta e de repositório podem ser
  # renomeados, deletados e re-registrados por OUTRA pessoa. Se a confiança
  # no Azure fosse ancorada só no texto "Pmacoy/azure-platform-engineering",
  # quem conseguisse registrar esse nome depois de você abandoná-lo herdaria
  # o acesso à sua subscription. Os IDs numéricos nunca são reaproveitados,
  # então ancorar neles fecha esse buraco.
  #
  # Consequência prática: o subject é comparado pelo Azure AD como string
  # exata e case-sensitive, então ele tem que ser montado exatamente neste
  # formato -- inclusive a capitalização do login (Pmacoy, não pmacoy).
  github_oidc_subject_prefix = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repository_id}"
}

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
  subject        = "${local.github_oidc_subject_prefix}:pull_request"
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
  subject        = "${local.github_oidc_subject_prefix}:environment:${var.github_environment}"
}

# Credencial usada pelo job de "plan" quando ele dispara por um PUSH direto
# na main (não por pull request) -- é o caso do workflow deste projeto, já
# que o job de apply depende do plan ter rodado no MESMO push. Fora de um
# Environment e fora de um pull_request, o token OIDC que o GitHub emite
# tem um terceiro formato de subject: "repo:<owner>/<repo>:ref:refs/heads/
# <branch>". Sem esta credencial, só a branch "main" (a única com proteção
# de branch/push direto neste projeto) consegue autenticar assim -- outras
# branches continuam sem acesso nenhum fora de PR ou do Environment gated.
resource "azuread_application_federated_identity_credential" "main_branch_push" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-push-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "${local.github_oidc_subject_prefix}:ref:refs/heads/main"
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
