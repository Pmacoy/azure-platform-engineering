# Ver o comentário equivalente em modules/aks/versions.tf: um módulo
# declara de quais providers depende, mas nunca os configura -- isso é
# sempre responsabilidade da raiz (environments/dev).

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
}
