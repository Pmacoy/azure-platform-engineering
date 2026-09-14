variable "prefix" {
  description = "Prefixo curto usado nos nomes dos recursos (ex: 'azpe-dev')."
  type        = string
}

variable "location" {
  description = "Região Azure onde o cluster e o registry são provisionados."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group onde o cluster e o registry vivem -- normalmente o da landing zone."
  type        = string
}

variable "subnet_id" {
  description = "ID da sub-rede onde os nós do cluster são injetados (a sub-rede privada da landing zone)."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace do Log Analytics para o Container Insights. null desliga o agente de monitoramento (e o custo de ingestão)."
  type        = string
  default     = null
}

# --- Dimensionamento e custo -------------------------------------------------

variable "node_vm_size" {
  description = <<-EOT
    Tamanho da VM dos nós. Standard_B2s (2 vCPU / 4 GB, série burstable) é
    o piso utilizável de um cluster AKS e a opção mais barata que funciona.
    Atenção para os próximos milestones: Argo CD (M3) cabe folgado, mas o
    Backstage (M4) é pesado de memória e provavelmente vai exigir subir
    para Standard_B2ms (8 GB). Graças ao temporary_name_for_rotation no
    main.tf, essa troca é uma rotação de pool, não a recriação do cluster.
  EOT
  type        = string
  default     = "Standard_B2s"
}

variable "node_count" {
  description = "Quantidade de nós no pool de sistema. 1 é o mínimo e o mais barato; sem alta disponibilidade, de propósito."
  type        = number
  default     = 1
}

variable "os_disk_size_gb" {
  description = "Tamanho do disco de SO de cada nó, em GB. O mínimo aceito pelo AKS é 30."
  type        = number
  default     = 32
}

variable "acr_sku" {
  description = "SKU do Container Registry. Basic é suficiente até o M4; Premium só importa para geo-replicação e private link."
  type        = string
  default     = "Basic"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes. null deixa o AKS usar o padrão da região."
  type        = string
  default     = null
}

# --- Rede --------------------------------------------------------------------

variable "pod_cidr" {
  description = "Espaço de IP dos pods no modo overlay. Não pode colidir com a VNet (10.20.0.0/16) nem com o service_cidr."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Espaço de IP dos Services do Kubernetes. Não pode colidir com a VNet nem com o pod_cidr."
  type        = string
  default     = "10.30.0.0/16"
}

variable "dns_service_ip" {
  description = "IP do CoreDNS dentro do cluster. Precisa estar dentro do service_cidr."
  type        = string
  default     = "10.30.0.10"
}

variable "network_policy" {
  description = "Engine de network policy ('calico', 'cilium' ou null). null mantém o cluster mínimo; ligar é trabalho do M5."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos deste módulo."
  type        = map(string)
  default     = {}
}
