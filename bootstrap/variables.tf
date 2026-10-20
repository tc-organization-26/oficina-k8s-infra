variable "aws_region" {
  description = "Regiao AWS usada pelos quatro repositorios."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nome globalmente unico do bucket que armazena os states Terraform."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Use um nome S3 valido, com letras minusculas, numeros, ponto ou hifen."
  }
}

variable "github_owner" {
  description = "Organizacao ou usuario proprietario dos quatro repositorios."
  type        = string
}

variable "github_owner_id" {
  description = "ID numerico imutavel da organizacao ou usuario no GitHub."
  type        = string
}

variable "github_repositories" {
  description = "Repositorios autorizados a assumir a role. Repositorios novos usam subject OIDC imutavel."
  type = map(object({
    repository_id     = string
    immutable_subject = bool
  }))

  validation {
    condition     = length(var.github_repositories) == 4
    error_message = "Informe exatamente os quatro repositorios do projeto."
  }

  validation {
    condition = alltrue([
      for repository in values(var.github_repositories) :
      !repository.immutable_subject || length(repository.repository_id) > 0
    ])
    error_message = "Todo repositorio com subject imutavel precisa do repository_id numerico."
  }
}

variable "github_actions_role_name" {
  description = "Nome da role compartilhada pelas pipelines do projeto."
  type        = string
  default     = "oficina-github-actions"
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN de um provider GitHub OIDC ja existente na conta; null cria um novo."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags aplicadas aos recursos do bootstrap."
  type        = map(string)
  default = {
    Project   = "oficina-fiap"
    ManagedBy = "Terraform"
    Component = "bootstrap"
  }
}
