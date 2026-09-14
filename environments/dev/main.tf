locals {
  prefix = "azpe-dev"

  tags = {
    project     = "azure-platform-engineering"
    environment = "dev"
    managed_by  = "terraform"
  }
}

module "landing_zone" {
  source = "../../modules/landing-zone"

  prefix   = local.prefix
  location = var.location
  tags     = local.tags
}

# M2: plataforma de execução (AKS) + registro de imagens (ACR).
#
# Repare que nada aqui é configurado duas vezes: o cluster entra na
# sub-rede privada que a landing zone criou, e manda métrica e log para o
# workspace que a landing zone criou. Essa é a diferença entre "camadas
# que se compõem" e "cada projeto criando a própria VNet" -- e é o
# argumento central de por que existe um módulo de landing zone separado.
module "aks" {
  source = "../../modules/aks"

  prefix              = local.prefix
  location            = var.location
  resource_group_name = module.landing_zone.resource_group_name
  subnet_id           = module.landing_zone.private_subnet_id
  tags                = local.tags

  log_analytics_workspace_id = module.landing_zone.log_analytics_workspace_id
}
