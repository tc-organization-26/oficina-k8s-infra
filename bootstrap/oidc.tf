resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_github_oidc_provider_arn == null ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_repository_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.github_actions_role_name
  description          = "Role OIDC usada pelos workflows dos quatro repositorios da oficina"
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid    = "TerraformInfrastructure"
    effect = "Allow"
    actions = [
      "apigateway:*",
      "autoscaling:*",
      "cloudwatch:*",
      "ec2:*",
      "eks:*",
      "elasticloadbalancing:*",
      "iam:*",
      "kms:*",
      "lambda:*",
      "logs:*",
      "rds:*",
      "secretsmanager:*",
      "ssm:*",
      "tag:*"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformStateBucket"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  statement {
    sid       = "AccountDiscovery"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "oficina-terraform-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
