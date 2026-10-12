terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/kms"
    },
    var.tags,
  )
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "key" {
  # Default key policy: root user can manage; explicit admin/usage principals layered on.
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_administrators) > 0 ? [1] : []
    content {
      sid    = "KeyAdministration"
      effect = "Allow"
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
        "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_administrators
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []
    content {
      sid    = "KeyUsage"
      effect = "Allow"
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []
    content {
      sid    = "AllowServiceUse"
      effect = "Allow"
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = var.service_principals
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation      = true
  rotation_period_in_days  = var.rotation_period_in_days
  multi_region             = var.multi_region
  policy                   = data.aws_iam_policy_document.key.json

  tags = merge(local.common_tags, {
    Name = var.alias
  })

  lifecycle {
    precondition {
      condition     = length(var.replica_regions) == 0 || var.multi_region
      error_message = "replica_regions requires multi_region = true; only multi-Region primary keys can be replicated."
    }
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

###############################################################################
# Multi-Region replicas
#
# One replica per region, created through the provider's resource-level
# `region` argument, so callers need no aliased providers. Replicas share the
# primary's key material and rotation schedule; the key policy, deletion window,
# alias and tags are applied per replica because AWS does not sync them.
###############################################################################

resource "aws_kms_replica_key" "this" {
  for_each = var.replica_regions

  region                  = each.key
  primary_key_arn         = aws_kms_key.this.arn
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  tags = merge(local.common_tags, {
    Name = var.alias
  })

  lifecycle {
    precondition {
      condition     = each.key != data.aws_region.current.region
      error_message = "replica_regions must not include the primary key's region (${data.aws_region.current.region})."
    }
  }
}

resource "aws_kms_alias" "replica" {
  for_each = var.replica_regions

  region        = each.key
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_replica_key.this[each.key].key_id
}
