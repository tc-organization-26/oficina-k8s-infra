output "aws_account_id" {
  description = "Conta que possui os recursos do projeto."
  value       = data.aws_caller_identity.current.account_id
}

output "github_actions_role_arn" {
  description = "Valor da variavel AWS_ROLE_ARN dos quatro repositorios."
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket_name" {
  description = "Valor da variavel TF_STATE_BUCKET dos repositorios Terraform."
  value       = aws_s3_bucket.terraform_state.id
}

output "oidc_provider_arn" {
  description = "Provider OIDC usado pelo GitHub Actions."
  value       = local.github_oidc_provider_arn
}
