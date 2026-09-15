# Workload Identity: uma identidade do Azure que um pod específico pode
# assumir, sem senha em lugar nenhum.
#
# Este módulo é o M1 repetido um andar abaixo, e vale enxergar o paralelo:
#
#   M1 (GitHub Actions)          │  M4 (pod no Kubernetes)
#   ─────────────────────────────┼──────────────────────────────────────
#   GitHub assina o token        │  o cluster AKS assina o token
#   "sou a execução X do repo Y" │  "sou a service account X do namespace Y"
#   subject:                     │  subject:
#     repo:owner/repo:contexto   │    system:serviceaccount:<ns>:<sa>
#   Azure AD confia no issuer    │  Azure AD confia no issuer
#   do GitHub                    │  do cluster
#
# Nos dois casos o Azure AD troca um token de curta duração, emitido por um
# terceiro em quem ele decidiu confiar, por um access token próprio. Nenhum
# segredo é guardado dos dois lados -- a confiança é na assinatura e no
# conteúdo do token, não numa senha compartilhada.

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# É este recurso que diz ao Azure AD: "aceite tokens emitidos por ESTE
# cluster que afirmem ser ESTA service account, deste namespace".
#
# O subject é comparado como string exata -- a mesma armadilha do M1. Se o
# pod rodar com outra service account, ou no namespace errado, o token não
# casa e a autenticação falha com "no matching federated identity record".
resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.name}-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id

  audience = ["api://AzureADTokenExchange"]
  issuer   = var.oidc_issuer_url
  subject  = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

# Permissão de LEITURA de segredos, nada mais.
#
# "Key Vault Secrets User" lê valores de segredo e só. Não lista, não
# escreve, não toca em chaves nem certificados. Comparar com "Key Vault
# Administrator" (que a maioria dos tutoriais usa) é a diferença entre um
# pod comprometido vazar um token do GitHub e um pod comprometido poder
# reescrever todos os segredos da plataforma.
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id

  # A identidade acabou de ser criada e leva alguns segundos para replicar
  # no Azure AD -- mesma razão do skip no role assignment do AcrPull no M2.
  skip_service_principal_aad_check = true
}
