terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/ecr"
    },
    var.tags,
  )

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  use_kms = var.encryption_type == "KMS"

  # Per-repository lifecycle settings: repository overrides win over the
  # module-level defaults.
  lifecycle_settings = {
    for name, repo in var.repositories : name => {
      untagged_expire_days = coalesce(repo.untagged_expire_days, var.lifecycle_untagged_expire_days)
      keep_tagged_count    = coalesce(repo.keep_tagged_count, var.lifecycle_keep_tagged_count)
      tagged_prefixes      = repo.tagged_prefixes != null ? repo.tagged_prefixes : var.lifecycle_tagged_prefixes
      keep_any_count       = repo.keep_any_count != null ? repo.keep_any_count : var.lifecycle_keep_any_count
    }
  }

  # Rules are listed in evaluation order; rulePriority is assigned from the
  # list position below, so the tagStatus = "any" rule always ends up with the
  # highest priority value, as ECR requires.
  lifecycle_rules = {
    for name, s in local.lifecycle_settings : name => concat(
      [
        {
          description = "Expire untagged images older than ${s.untagged_expire_days} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = s.untagged_expire_days
          }
          action = { type = "expire" }
        },
      ],
      length(s.tagged_prefixes) > 0 ? [
        {
          description = "Keep the last ${s.keep_tagged_count} images tagged ${join(", ", s.tagged_prefixes)}*"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = s.tagged_prefixes
            countType     = "imageCountMoreThan"
            countNumber   = s.keep_tagged_count
          }
          action = { type = "expire" }
        },
      ] : [],
      s.keep_any_count != null ? [
        {
          description = "Keep the last ${s.keep_any_count} images not matched by an earlier rule"
          selection = {
            tagStatus   = "any"
            countType   = "imageCountMoreThan"
            countNumber = s.keep_any_count
          }
          action = { type = "expire" }
        },
      ] : [],
    )
  }

  # Bare account IDs are expanded to the account root ARN so the stored policy
  # matches what ECR returns and does not show a perpetual diff.
  principal_arns = {
    for name, repo in var.repositories : name => {
      pull = [for p in repo.pull_principals : can(regex("^[0-9]{12}$", p)) ? "arn:${local.partition}:iam::${p}:root" : p]
      push = [for p in repo.push_principals : can(regex("^[0-9]{12}$", p)) ? "arn:${local.partition}:iam::${p}:root" : p]
    }
  }

  # Lambda functions allowed to pull: this account plus every pull principal's
  # account. Lambda only pulls from a repository in its own Region.
  lambda_source_arns = {
    for name, repo in var.repositories : name => [
      for acct in distinct(concat(
        [local.account_id],
        [for p in repo.pull_principals : can(regex("^[0-9]{12}$", p)) ? p : split(":", p)[4]],
      )) : "arn:${local.partition}:lambda:${local.region}:${acct}:function:*"
    ]
  }

  repositories_with_policy = {
    for name, repo in var.repositories : name => repo
    if length(repo.pull_principals) > 0 || length(repo.push_principals) > 0 || repo.lambda_pull
  }

  pull_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
  ]

  push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:CompleteLayerUpload",
    "ecr:GetDownloadUrlForLayer",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

###############################################################################
# Repositories
###############################################################################

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  # Encryption settings are fixed at creation; changing them replaces the
  # repository (and deletes its images).
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = local.use_kms ? var.kms_key_arn : null
  }

  tags = merge(local.common_tags, {
    Name = each.key
  })
}

###############################################################################
# Lifecycle policies
###############################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name
  policy = jsonencode({
    rules = [
      for i, rule in local.lifecycle_rules[each.key] : merge(rule, { rulePriority = i + 1 })
    ]
  })
}

###############################################################################
# Repository policies (only for repositories with principals or lambda_pull)
###############################################################################

data "aws_iam_policy_document" "repository" {
  for_each = local.repositories_with_policy

  dynamic "statement" {
    for_each = length(each.value.pull_principals) > 0 ? [1] : []
    content {
      sid     = "CrossAccountPull"
      effect  = "Allow"
      actions = local.pull_actions

      principals {
        type        = "AWS"
        identifiers = local.principal_arns[each.key].pull
      }
    }
  }

  dynamic "statement" {
    for_each = length(each.value.push_principals) > 0 ? [1] : []
    content {
      sid     = "CrossAccountPush"
      effect  = "Allow"
      actions = local.push_actions

      principals {
        type        = "AWS"
        identifiers = local.principal_arns[each.key].push
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.lambda_pull ? [1] : []
    content {
      sid     = "LambdaPull"
      effect  = "Allow"
      actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]

      principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "aws:sourceArn"
        values   = local.lambda_source_arns[each.key]
      }
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each = local.repositories_with_policy

  repository = aws_ecr_repository.this[each.key].name
  policy     = data.aws_iam_policy_document.repository[each.key].json
}

###############################################################################
# Registry-level settings (optional, off by default)
#
# Each of these is a singleton for the whole registry (account + Region):
# applying it here overwrites whatever was configured before, and two stacks
# that both manage it will overwrite each other on every apply. Enable them in
# exactly one stack per account and Region.
###############################################################################

resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.registry_scanning != null ? 1 : 0

  scan_type = var.registry_scanning.scan_type

  dynamic "rule" {
    for_each = var.registry_scanning.rules
    content {
      scan_frequency = rule.value.scan_frequency

      repository_filter {
        filter      = rule.value.filter
        filter_type = "WILDCARD"
      }
    }
  }
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.pull_through_cache_rules

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = each.value.credential_arn
}

resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_regions
        content {
          region      = destination.value
          registry_id = local.account_id
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !contains(var.replication_regions, local.region)
      error_message = "replication_regions must not include the registry's own Region (${local.region})."
    }
  }
}
