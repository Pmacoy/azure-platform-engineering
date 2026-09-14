variable "prefix" {
  description = "Prefixo curto usado em todos os nomes de recursos (ex: 'azpe-dev')."
  type        = string
}

variable "location" {
  description = "Região Azure onde os recursos são provisionados."
  type        = string
}

variable "vnet_address_space" {
  description = "Bloco CIDR da VNet inteira."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_prefix" {
  description = "Bloco CIDR da sub-rede pública (Load Balancer, Application Gateway, etc.)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_prefix" {
  description = "Bloco CIDR da sub-rede privada (cargas de trabalho -- futuramente o AKS da Fase 04)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "log_retention_days" {
  description = "Retenção de logs no Log Analytics Workspace, em dias."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos deste módulo."
  type        = map(string)
  default     = {}
}
