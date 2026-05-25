terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
      Module      = "terraform-aws-blueprint/s3-secure"
    },
    var.tags,
  )

  use_kms       = var.sse_algorithm == "aws:kms"
  use_name_only = var.bucket_name != null
}

###############################################################################
# Bucket
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket        = local.use_name_only ? var.bucket_name : null
  bucket_prefix = local.use_name_only ? null : var.bucket_name_prefix
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = local.use_name_only ? var.bucket_name : var.bucket_name_prefix
  })
}

###############################################################################
# Public access lockdown (all 4 settings)
###############################################################################

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

###############################################################################
# Ownership controls (BucketOwnerEnforced disables ACLs entirely)
###############################################################################

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

###############################################################################
# Versioning
###############################################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}

###############################################################################
# Server-side encryption
###############################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.use_kms
  }
}

###############################################################################
# Lifecycle rules
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.enable_lifecycle_rules ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "tiering-and-expiration"
    status = "Enabled"

    filter {
      prefix = var.lifecycle_prefix
    }

    dynamic "transition" {
      for_each = var.transition_to_ia_days != null ? [var.transition_to_ia_days] : []
      content {
        days          = transition.value
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.transition_to_glacier_days != null ? [var.transition_to_glacier_days] : []
      content {
        days          = transition.value
        storage_class = "GLACIER"
      }
    }

    dynamic "expiration" {
      for_each = var.expiration_days != null ? [var.expiration_days] : []
      content {
        days = expiration.value
      }
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.versioning_enabled && var.noncurrent_version_transition_days != null ? [var.noncurrent_version_transition_days] : []
      content {
        noncurrent_days = noncurrent_version_transition.value
        storage_class   = "GLACIER"
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.versioning_enabled && var.noncurrent_version_expiration_days != null ? [var.noncurrent_version_expiration_days] : []
      content {
        noncurrent_days = noncurrent_version_expiration.value
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

###############################################################################
# Access logging (optional)
###############################################################################

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logging_target_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logging_target_bucket
  target_prefix = var.access_logging_target_prefix != null ? var.access_logging_target_prefix : "${aws_s3_bucket.this.id}/"
}

###############################################################################
# CORS (optional)
###############################################################################

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }
}

###############################################################################
# Bucket policy: deny non-TLS and (optionally) deny unencrypted PUTs
###############################################################################

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.deny_unencrypted_object_uploads ? [1] : []
    content {
      sid       = "DenyUnencryptedObjectUploads"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.extra_policy_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "principals" {
        for_each = lookup(statement.value, "principals", [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
