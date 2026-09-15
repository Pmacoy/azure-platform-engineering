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

  # M3: subiu de Standard_B2s (4 GB) para Standard_B2ms (8 GB) porque o Argo
  # CD, mesmo enxuto, não cabe com folga ao lado do kube-system e do agente do
  # Container Insights num nó de 4 GB.
  #
  # Repare que isto é uma ROTAÇÃO de pool, não a recriação do cluster -- e é
  # exatamente por isso que o `temporary_name_for_rotation` foi colocado no
  # módulo no M2, antes de existir motivo para usá-lo. O plano deste apply é a
  # prova de que aquela decisão valeu: sem ela, esta linha destruiria o
  # cluster inteiro.
  node_vm_size = "Standard_B2ms"

  # Object ID do service principal criado pelo bootstrap (output
  # `azure_client_id` é o client ID; este é o object ID do service principal,
  # visível no state do bootstrap ou via:
  #   az ad sp show --id <client-id> --query id -o tsv
  # Não é segredo -- é um identificador, como o subscription ID.
  ci_principal_object_id = "e93aafd1-ee35-459f-abaf-e9216b3df1c4"
}
