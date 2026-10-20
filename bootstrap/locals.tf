locals {
  github_oidc_provider_arn = var.existing_github_oidc_provider_arn != null ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn

  github_repository_subjects = [
    for name, repository in var.github_repositories :
    repository.immutable_subject
    ? "repo:${var.github_owner}@${var.github_owner_id}/${name}@${repository.repository_id}:*"
    : "repo:${var.github_owner}/${name}:*"
  ]
}
