# O bootstrap roda uma única vez, localmente, com estado LOCAL de propósito.
# Ele existe para resolver o problema do ovo e da galinha: o backend remoto
# do Terraform (Storage Account) e a identidade que o GitHub Actions vai
# usar (App Registration + federated credential) ainda não existem -- e não
# dá para guardar o estado de "como criar o backend remoto" *dentro* do
# backend remoto que ele mesmo está criando.
#
# Por isso este diretório nunca ganha um bloco `backend "azurerm" {}`. O
# arquivo terraform.tfstate gerado aqui fica só na sua máquina (não vai pro
# Git -- veja o .gitignore na raiz do repo).

terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.10.0, < 5.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.53.0, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }
}

provider "azurerm" {
  # shared_access_key_enabled = false no storage account (main.tf) desliga a
  # chave de acesso -- mas isso só vale pro RECURSO em si. O PROVIDER
  # também precisa saber que, ao falar com o plano de dados do Storage
  # (criar container, checar se o blob service já está pronto depois do
  # create), ele deve usar uma identidade do Azure AD em vez de tentar uma
  # chave que não existe mais. Sem isto: 403
  # "Key based authentication is not permitted on this storage account".
  storage_use_azuread = true

  features {}
}

provider "azuread" {}
