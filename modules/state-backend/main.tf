terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/state-backend"
    },
    var.tags,
  )

  bucket_name = var.bucket_name

  # Replication: the module creates a role only when the caller did not supply one.
  enable_replication      = var.replication != null
  create_replication_role = local.enable_replication && try(var.replication.role_arn, null) == null
  replication_role_arn    = local.enable_replication ? coalesce(try(var.replication.role_arn, null), try(aws_iam_role.replication[0].arn, null)) : null
}

###############################################################################
# State bucket
###############################################################################

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = local.bucket_name
    Purpose = "terraform-state"
  })
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

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
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

###############################################################################
# Access logging (optional)
###############################################################################

resource "aws_s3_bucket_logging" "state" {
  count = var.access_logging != null ? 1 : 0

  bucket        = aws_s3_bucket.state.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix != null ? var.access_logging.target_prefix : "${aws_s3_bucket.state.id}/"
}

###############################################################################
# Replication for state DR (optional)
#
# Delete markers are not replicated: removing a state object (e.g. deleting a
# workspace) in the primary must not remove the DR copy.
###############################################################################

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
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "SourceObjectRead"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "DestinationObjectWrite"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${var.replication.destination_bucket_arn}/*"]
  }

  # Encryption context is the bucket ARN with S3 Bucket Keys, the object ARN
  # without — allow both so the policy holds either way.
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "SourceKmsDecrypt"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
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

  name_prefix        = "tfstate-replication-"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
  description        = "S3 replication role for Terraform state bucket ${local.bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.bucket_name}-replication"
  })
}

resource "aws_iam_role_policy" "replication" {
  count = local.create_replication_role ? 1 : 0

  name_prefix = "tfstate-replication-"
  role        = aws_iam_role.replication[0].id
  policy      = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "state" {
  count = local.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.state.id
  role   = local.replication_role_arn

  rule {
    id     = "state-dr"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    # SSE-KMS objects are skipped by replication unless opted in explicitly.
    dynamic "source_selection_criteria" {
      for_each = var.kms_key_arn != null ? [1] : []
      content {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }

    destination {
      bucket = var.replication.destination_bucket_arn

      dynamic "encryption_configuration" {
        for_each = var.replication.destination_kms_key_arn != null ? [var.replication.destination_kms_key_arn] : []
        content {
          replica_kms_key_id = encryption_configuration.value
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.state, aws_iam_role_policy.replication]
}

###############################################################################
# DynamoDB lock table (optional)
#
# Terraform >= 1.10 can lock with the state bucket alone (`use_lockfile`);
# 1.11 deprecates `dynamodb_table`. Set enable_dynamodb_lock = false to drop
# the table and emit `use_lockfile = true` in backend_config_hcl instead.
###############################################################################

moved {
  from = aws_dynamodb_table.lock
  to   = aws_dynamodb_table.lock[0]
}

resource "aws_dynamodb_table" "lock" {
  count = var.enable_dynamodb_lock ? 1 : 0

  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = true

  tags = merge(local.common_tags, {
    Name    = var.lock_table_name
    Purpose = "terraform-state-lock"
  })
}

###############################################################################
# backend_config_hcl bodies
###############################################################################

# Both bodies are always evaluated, so the table reference uses join() — an
# empty string when the table is disabled — instead of interpolating null.
locals {
  backend_config_dynamodb = <<-EOT
    bucket         = "${aws_s3_bucket.state.id}"
    key            = "<stack-name>/terraform.tfstate"
    region         = "${data.aws_region.current.region}"
    dynamodb_table = "${join("", aws_dynamodb_table.lock[*].name)}"
    encrypt        = true
  EOT

  backend_config_lockfile = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "<stack-name>/terraform.tfstate"
    region       = "${data.aws_region.current.region}"
    use_lockfile = true
    encrypt      = true
  EOT
}
