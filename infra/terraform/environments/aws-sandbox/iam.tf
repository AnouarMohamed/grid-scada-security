resource "aws_iam_role" "ecs_execution" {
  name                 = "${local.name}-ecs-execution"
  permissions_boundary = var.workload_role_permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets" {
  count = var.enable_runtime ? 1 : 0

  name = "${local.name}-runtime-secrets"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadRuntimeSecrets"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = values(aws_secretsmanager_secret.runtime)[*].arn
    }]
  })
}

resource "aws_iam_role" "ecs_storage" {
  for_each = var.enable_runtime ? local.stateful_services : toset([])

  name                 = "${local.name}-${each.key}-task"
  permissions_boundary = var.workload_role_permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_efs" {
  for_each = aws_iam_role.ecs_storage

  name = "${local.name}-${each.key}-efs-client"
  role = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "MountOwnFilesystem"
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
      ]
      Resource = aws_efs_file_system.service[each.key].arn
      Condition = {
        StringEquals = {
          "elasticfilesystem:AccessPointArn" = aws_efs_access_point.service[each.key].arn
        }
      }
    }]
  })
}

data "tls_certificate" "github" {
  count = var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.github[0].certificates[
      length(data.tls_certificate.github[0].certificates) - 1
    ].sha1_fingerprint
  ]
}

locals {
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : var.github_oidc_provider_arn
  )
  github_subjects = [
    for environment in var.github_environments :
    "repo:${var.github_repository}:environment:${environment}"
  ]
}

resource "aws_iam_role" "github_deploy" {
  count = var.enable_github_oidc_role ? 1 : 0

  name = "${local.name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubEnvironmentTrust"
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.github_oidc_provider_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.github_subjects
        }
      }
    }]
  })
  permissions_boundary = var.github_role_permissions_boundary_arn

  description = "GitHub Actions deployment role; permissions are supplied separately."
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  count = var.enable_github_oidc_role && var.github_deploy_policy_arn != null ? 1 : 0

  role       = aws_iam_role.github_deploy[0].name
  policy_arn = var.github_deploy_policy_arn
}
