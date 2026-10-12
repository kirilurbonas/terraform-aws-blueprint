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
      Module      = "terraform-aws-blueprint/s3-secure"
    },
    var.tags,
  )

  use_kms       = var.sse_algorithm == "aws:kms"
  use_name_only = var.bucket_name != null

  # Replication: the module creates a role only when the caller did not supply one.
  enable_replication      = var.replication != null
  create_replication_role = local.enable_replication && try(var.replication.role_arn, null) == null
  replication_role_arn    = local.enable_replication ? coalesce(try(var.replication.role_arn, null), try(aws_iam_role.replication[0].arn, null)) : null
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
    for_each = var.deny_unencrypted_object_uploads ? [1] : []
    content {
      sid       = "DenyIncorrectEncryptionHeader"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption"
        values   = [var.sse_algorithm]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deny_unencrypted_object_uploads && local.use_kms ? [1] : []
    content {
      sid       = "DenyMissingKmsKeyId"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deny_unencrypted_object_uploads && local.use_kms ? [1] : []
    content {
      sid       = "DenyIncorrectKmsKeyId"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [var.kms_key_arn]
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

###############################################################################
# Object Lock (optional)
#
# Enabled through the configuration resource rather than the bucket's
# `object_lock_enabled` argument: that argument forces replacement of an
# existing bucket, while PutObjectLockConfiguration can enable Object Lock in
# place on any versioned bucket. Object Lock cannot be disabled once enabled.
###############################################################################

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock != null ? 1 : 0

  bucket              = aws_s3_bucket.this.id
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode  = var.object_lock.mode
      days  = var.object_lock.days
      years = var.object_lock.years
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

###############################################################################
# Replication (optional)
###############################################################################

data "aws_region" "current" {
  count = local.enable_replication ? 1 : 0
}

data "aws_iam_policy_document" "replication_assume" {
  count = local.create_replication_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replication" {
  count = local.create_replication_role ? 1 : 0

  statement {
    sid       = "SourceBucketConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "SourceObjectRead"
    actions = concat(
      [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging",
      ],
      # Retention and legal-hold metadata travel with locked objects.
      var.object_lock != null ? ["s3:GetObjectRetention", "s3:GetObjectLegalHold"] : [],
    )
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "DestinationObjectWrite"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${var.replication.destination_bucket_arn}/*"]
  }

  # Encryption context is the bucket ARN with S3 Bucket Keys, the object ARN
  # without — allow both so the policy holds either way.
  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "SourceKmsDecrypt"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current[0].region}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.replication.destination_kms_key_arn != null ? [1] : []
    content {
      sid       = "DestinationKmsEncrypt"
      actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
      resources = [var.replication.destination_kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${split(":", var.replication.destination_kms_key_arn)[3]}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = [var.replication.destination_bucket_arn, "${var.replication.destination_bucket_arn}/*"]
      }
    }
  }
}

resource "aws_iam_role" "replication" {
  count = local.create_replication_role ? 1 : 0

  name_prefix        = "s3-replication-"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
  description        = "S3 replication role for ${aws_s3_bucket.this.id}"

  tags = merge(local.common_tags, {
    Name = "${aws_s3_bucket.this.id}-replication"
  })
}

resource "aws_iam_role_policy" "replication" {
  count = local.create_replication_role ? 1 : 0

  name_prefix = "s3-replication-"
  role        = aws_iam_role.replication[0].id
  policy      = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = local.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.this.id
  role   = local.replication_role_arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    # An empty filter selects the V2 rule schema, which is what makes
    # delete_marker_replication configurable.
    filter {}

    delete_marker_replication {
      status = var.replication.delete_marker_replication ? "Enabled" : "Disabled"
    }

    # SSE-KMS objects are skipped by replication unless opted in explicitly.
    dynamic "source_selection_criteria" {
      for_each = local.use_kms ? [1] : []
      content {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }

    destination {
      bucket        = var.replication.destination_bucket_arn
      storage_class = var.replication.storage_class

      dynamic "encryption_configuration" {
        for_each = var.replication.destination_kms_key_arn != null ? [var.replication.destination_kms_key_arn] : []
        content {
          replica_kms_key_id = encryption_configuration.value
        }
      }
    }
  }

  # Replication requires versioning to be enabled first, and the role's
  # permissions to exist before S3 validates them.
  depends_on = [aws_s3_bucket_versioning.this, aws_iam_role_policy.replication]
}

###############################################################################
# EventBridge notifications (optional)
#
# aws_s3_bucket_notification owns the bucket's entire notification
# configuration. Do not enable this and also manage SNS / SQS / Lambda
# notifications for the same bucket elsewhere — the two will overwrite each
# other.
###############################################################################

resource "aws_s3_bucket_notification" "this" {
  count = var.enable_eventbridge_notifications ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

###############################################################################
# Intelligent-Tiering archive configurations (optional)
#
# These only act on objects already in the INTELLIGENT_TIERING storage class;
# they add the opt-in Archive / Deep Archive access tiers on top of it.
###############################################################################

resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  for_each = var.intelligent_tiering

  bucket = aws_s3_bucket.this.id
  name   = each.key
  status = each.value.enabled ? "Enabled" : "Disabled"

  dynamic "filter" {
    for_each = each.value.prefix != null || each.value.tags != null ? [1] : []
    content {
      prefix = each.value.prefix
      tags   = each.value.tags
    }
  }

  dynamic "tiering" {
    for_each = each.value.archive_access_days != null ? [each.value.archive_access_days] : []
    content {
      access_tier = "ARCHIVE_ACCESS"
      days        = tiering.value
    }
  }

  dynamic "tiering" {
    for_each = each.value.deep_archive_access_days != null ? [each.value.deep_archive_access_days] : []
    content {
      access_tier = "DEEP_ARCHIVE_ACCESS"
      days        = tiering.value
    }
  }
}
