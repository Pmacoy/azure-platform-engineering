# ---------------------------------------------------------------------------
# Azure Container Registry
#
# admin_enabled = false de propósito. O ACR pode gerar um usuário e senha
# estáticos ("admin user") que você colaria num imagePullSecret do
# Kubernetes -- que é exatamente o tipo de segredo de longa duração que o
# resto deste projeto passou o M1 inteiro eliminando. Em vez disso, a
# identidade do próprio cluster recebe a role AcrPull mais abaixo.
# ---------------------------------------------------------------------------

resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_container_registry" "this" {
  # Nome do ACR é único GLOBALMENTE no Azure inteiro e só aceita
  # alfanumérico (sem hífen), daí o replace e o sufixo aleatório.
  name                = "${replace(var.prefix, "-", "")}acr${random_string.acr_suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# AKS
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.prefix}-aks"

  # null = deixa o AKS escolher a versão padrão da região. Fixar a versão
  # aqui é o certo para produção (upgrade vira decisão explícita), mas num
  # projeto de estudo fixar significa quebrar sozinho quando a versão sair
  # de suporte e o Azure recusar o create.
  kubernetes_version = var.kubernetes_version

  # Free = control plane sem custo e sem SLA financeiro. "Standard" dá SLA
  # e custa por hora. Para estudo, Free é a escolha óbvia; saber que essa
  # escolha existe e o que ela compra é o que importa numa entrevista.
  sku_tier = "Free"

  # O AKS cria um resource group SEPARADO, gerenciado por ele, onde vivem
  # as VMs, discos e o load balancer. Nomear explicitamente evita o padrão
  # feio ("MC_azpe-dev-rg_azpe-dev-aks_eastus2") e deixa claro na fatura
  # de onde vem o custo.
  node_resource_group = "${var.prefix}-aks-nodes"

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.subnet_id

    # Disco de SO menor que o padrão (128 GB) -- disco gerenciado é
    # cobrado por GB provisionado, não por GB usado.
    os_disk_size_gb = var.os_disk_size_gb

    # Sem isto, mudar o vm_size do pool padrão força a DESTRUIÇÃO e
    # recriação do cluster inteiro. Com isto, o provider cria um pool
    # temporário com este nome, move as cargas, recria o pool definitivo
    # no tamanho novo e remove o temporário. É a diferença entre "trocar o
    # tamanho do nó" ser um upgrade e ser um incidente.
    temporary_name_for_rotation = "systemtmp"
  }

  # Identidade gerenciada pelo próprio Azure, sem segredo: o cluster usa
  # ela para criar load balancers, discos, etc. Mesma filosofia do OIDC do
  # M1 -- nada que precise ser rotacionado à mão.
  identity {
    type = "SystemAssigned"
  }

  # WORKLOAD IDENTITY (M4) -- o mesmo mecanismo do M1, um andar abaixo.
  #
  # No M1, o GitHub emitia um token OIDC dizendo "sou a execução X do
  # repositório Y", e o Azure AD trocava por um access token. Aqui o
  # EMISSOR passa a ser o próprio cluster: ele assina um token dizendo "sou
  # a service account tal, do namespace tal", e o Azure AD troca pelo
  # mesmo tipo de access token.
  #
  # `oidc_issuer_enabled` liga o emissor (publica as chaves públicas num
  # endpoint que o Azure AD consegue consultar). `workload_identity_enabled`
  # liga o webhook que injeta o token projetado nos pods que pedirem.
  #
  # O resultado é que um pod consegue ler um segredo do Key Vault sem que
  # exista senha nenhuma em lugar nenhum -- nem em YAML, nem no Git, nem
  # num Secret do Kubernetes.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Addon que monta segredos do Key Vault como arquivos dentro do pod.
  # A rotação relê o Key Vault periodicamente: sem ela, trocar um segredo
  # no cofre não teria efeito até o pod ser recriado.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  network_profile {
    network_plugin = "azure"

    # Overlay: os pods recebem IPs de um espaço próprio (pod_cidr), não da
    # sub-rede da VNet. Sem isso, o Azure CNI clássico reserva um IP da
    # sub-rede para CADA pod -- uma /24 como a nossa esgotaria com poucas
    # dezenas de pods. Overlay é o padrão recomendado hoje justamente por
    # isso, e é o que permite a landing zone ter sub-redes pequenas.
    network_plugin_mode = "overlay"

    # null = sem engine de network policy. Calico/Cilium rodam pods extras
    # que consomem memória que um nó pequeno não tem sobrando. Ligar
    # network policy é trabalho do M5 (guardrails), junto com Azure Policy.
    network_policy = var.network_policy

    load_balancer_sku = "standard"

    # Os três blocos abaixo não podem se sobrepor entre si nem com o
    # espaço da VNet (10.20.0.0/16 na landing zone). Deixar explícito
    # evita a surpresa clássica de o padrão do AKS colidir com uma rede
    # on-premises conectada por VPN mais tarde.
    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  # Container Insights escrevendo no MESMO workspace que a landing zone
  # criou no M1 -- é o primeiro consumidor real dele. Opcional porque a
  # ingestão de log é cobrada por GB; num cluster de 1 nó ocioso é
  # centavos, mas a alavanca existe.
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id == null ? [] : [1]
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Ligação AKS -> ACR
#
# O `az aks update --attach-acr` da documentação faz exatamente isto por
# baixo: cria um role assignment de AcrPull para a identidade do kubelet.
# Fazer declarativamente significa que a ligação está no código, versionada
# e recriável -- e não num comando que alguém rodou uma vez e ninguém
# lembra.
#
# A identidade do kubelet é DIFERENTE da identidade do cluster: o cluster
# usa a dele para gerenciar recursos do Azure (load balancer, disco), e os
# nós usam a do kubelet para puxar imagem. É a do kubelet que precisa de
# AcrPull.
# ---------------------------------------------------------------------------

# Permissão de PUSH para a identidade do pipeline.
#
# Sutileza que vale entender: a identidade do GitHub Actions já é Contributor
# na assinatura, e o Contributor tecnicamente consegue empurrar imagem, porque
# as permissões de push/pull do ACR estão declaradas em `actions` (cobertas
# pelo curinga do Contributor) e não em `dataActions` (que curinga nenhum
# alcança). Ou seja: funcionaria por acidente da forma como a Microsoft
# modelou essa role.
#
# Depender disso é frágil -- o dia em que o Contributor for reduzido, ou o
# escopo apertado no M5, o pipeline quebra sem ninguém entender por quê.
# Declarar AcrPush explicitamente torna a intenção legível e sobrevive ao
# aperto de escopo que já está planejado.
resource "azurerm_role_assignment" "ci_acr_push" {
  count = var.ci_principal_object_id == null ? 0 : 1

  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "AcrPush"
  principal_id                     = var.ci_principal_object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id

  # A identidade gerenciada acabou de ser criada pelo AKS e leva alguns
  # segundos para replicar no Azure AD. Sem isto, o provider valida o
  # principal antes da replicação terminar e falha com "PrincipalNotFound"
  # de forma intermitente -- o tipo de erro que passa no seu apply e
  # quebra no de outra pessoa.
  skip_service_principal_aad_check = true
}
