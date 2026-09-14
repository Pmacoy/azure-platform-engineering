# Um módulo reutilizável declara de quais providers ele depende. Sem isto
# ele funciona por herança da raiz, mas passa a depender de a raiz ter
# declarado os providers certos -- e quebra de um jeito confuso quando o
# módulo é reusado num projeto que não declarou.
#
# Repare que aqui NÃO existe bloco `provider`: módulo declara do que
# precisa, quem configura (subscription, autenticação) é sempre a raiz.

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
