variable "aws_region" {
  description = "Regiao AWS dos recursos."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "oficina"
}

variable "environment" {
  description = "Nome do ambiente."
  type        = string
  default     = "dev"
}

variable "lab_role_arn" {
  description = "ARN da LabRole preexistente, reutilizada pelo EKS e pelos nodes no ambiente educacional."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.lab_role_arn))
    error_message = "lab_role_arn deve ser o ARN de uma role IAM valida."
  }
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_version" {
  description = "Versao do Kubernetes suportada pelo EKS."
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "Tipos de instancia do managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "enable_nat_gateway" {
  description = "Habilita NAT Gateway para os nos privados. Gera custo adicional."
  type        = bool
  default     = true
}

variable "app_node_port" {
  description = "NodePort reservado para a aplicacao principal."
  type        = number
  default     = 30081
}
