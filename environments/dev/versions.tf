terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.10.0, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }

  # Preenchido em tempo de `init` via -backend-config (no CI) ou
  # backend.hcl local (não commitado -- veja o README). Fica vazio aqui de
  # propósito: nenhuma credencial ou nome de recurso específico do ambiente
  # vive hardcoded no código.
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
