# ---------------------------------------------------------------------------
# Landing zone mínima -- Fase 02 / Milestone 1 do roteiro.
#
# Este módulo é deliberadamente pequeno: um resource group, uma VNet com
# duas sub-redes (pública/privada) cada uma com sua própria NSG, um
# workspace central de logs e um Key Vault. É a base sob a qual tudo o
# resto do roteiro (AKS na Fase 04, segredos da Fase 06) vai se apoiar --
# por isso vive num módulo reutilizável em vez de solto no environment,
# exatamente a lição da Fase 02: "20 times não deviam escrever 20 Terraforms
# diferentes para o mesmo problema".
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet" "public" {
  name                 = "${var.prefix}-snet-public"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.public_subnet_prefix]
}

resource "azurerm_subnet" "private" {
  name                 = "${var.prefix}-snet-private"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_subnet_prefix]

  # Service endpoint para Key Vault (M4).
  #
  # Sem isto, o tráfego desta sub-rede sai para o Key Vault pela internet,
  # com o IP público de saída do cluster -- um IP que o AKS gerencia e que
  # pode mudar. Liberar aquele IP no firewall do Key Vault seria uma regra
  # que quebra sozinha algum dia.
  #
  # Com o service endpoint, o tráfego passa a sair pela espinha dorsal da
  # Azure com a IDENTIDADE DA SUB-REDE, e o Key Vault pode confiar na
  # sub-rede em vez de num endereço. A regra passa a descrever quem está
  # falando, não de onde.
  service_endpoints = ["Microsoft.KeyVault"]
}

# A sub-rede pública só aceita HTTPS de entrada. Tudo o mais fica de fora
# por padrão -- NSGs no Azure negam implicitamente o que não é permitido
# explicitamente, mas a regra abaixo deixa a intenção legível em vez de
# depender do comportamento implícito.
resource "azurerm_network_security_group" "public" {
  name                = "${var.prefix}-nsg-public"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# A sub-rede privada nega explicitamente qualquer coisa vinda direto da
# internet, e só libera tráfego entre recursos dentro da própria VNet --
# uma carga de trabalho aqui dentro nunca deveria ser alcançável de fora
# sem passar pela sub-rede pública primeiro.
resource "azurerm_network_security_group" "private" {
  name                = "${var.prefix}-nsg-private"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "deny-internet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.prefix}-log"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# Nome de Key Vault é único *globalmente* em todo o Azure, não só dentro da
# assinatura -- daí o sufixo aleatório em vez de só "${var.prefix}-kv".
# RBAC em vez de access policies porque combina com o resto do projeto: a
# mesma identidade OIDC do GitHub Actions ganha acesso via role assignment,
# não via uma lista de policies separada e fácil de esquecer de atualizar.
resource "azurerm_key_vault" "this" {
  name                = "${var.prefix}-kv-${random_string.kv_suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true

  # "Deny" por padrão: nada alcança o plano de dados deste Key Vault a não
  # ser o que estiver explicitamente liberado abaixo.
  #
  # A sub-rede privada entra na lista (M4) porque é lá que os pods rodam, e
  # o driver CSI precisa ler segredos daqui. Repare que a liberação é por
  # SUB-REDE, não por IP: quem autoriza é a identidade de rede, que não muda
  # quando o IP público de saída do cluster mudar.
  #
  # O pipeline de CI continua de fora de propósito. Ele roda em runners da
  # GitHub, fora da rede do Azure, e não tem motivo para ler segredo nenhum
  # -- ele provisiona o Key Vault (plano de controle, via ARM), não consome
  # o conteúdo dele.
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.private.id]
  }

  tags = var.tags
}
