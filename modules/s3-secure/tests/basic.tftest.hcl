mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  environment        = "dev"
  project            = "blueprint-tests"
  bucket_name_prefix = "blueprint-test-"
}

run "defaults_plan_cleanly" {
  command = plan
}

run "kms_mode_requires_no_extra_setup" {
  command = plan

  variables {
    sse_algorithm = "aws:kms"
    kms_key_arn   = "arn:aws:kms:us-east-1:111122223333:key/EXAMPLE"
  }

  assert {
    condition = contains(
      flatten([
        for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule : [
          for enc in rule.apply_server_side_encryption_by_default : enc.kms_master_key_id
        ]
      ]),
      "arn:aws:kms:us-east-1:111122223333:key/EXAMPLE",
    )
    error_message = "kms mode should wire the configured KMS key into bucket encryption"
  }
}

run "rejects_bad_sse" {
  command         = plan
  expect_failures = [var.sse_algorithm]

  variables {
    sse_algorithm = "DES"
  }
}

run "rejects_missing_bucket_name_inputs" {
  command         = plan
  expect_failures = [var.bucket_name]

  variables {
    bucket_name_prefix = null
  }
}

run "rejects_kms_mode_without_kms_key" {
  command         = plan
  expect_failures = [var.kms_key_arn]

  variables {
    sse_algorithm = "aws:kms"
    kms_key_arn   = null
  }
}

run "cors_rule_renders" {
  command = plan

  variables {
    cors_rules = [
      {
        allowed_methods = ["GET"]
        allowed_origins = ["https://example.com"]
      },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 1
    error_message = "expected cors config when cors_rules is non-empty"
  }
}

run "defaults_create_no_optional_resources" {
  command = plan

  assert {
    condition = (
      length(aws_s3_bucket_object_lock_configuration.this) == 0 &&
      length(aws_s3_bucket_replication_configuration.this) == 0 &&
      length(aws_iam_role.replication) == 0 &&
      length(aws_s3_bucket_notification.this) == 0 &&
      length(aws_s3_bucket_intelligent_tiering_configuration.this) == 0
    )
    error_message = "object lock, replication, notifications and intelligent-tiering must be off by default"
  }

  assert {
    condition     = output.replication_role_arn == null
    error_message = "replication_role_arn should be null when replication is disabled"
  }
}

###############################################################################
# Object Lock
###############################################################################

run "object_lock_renders" {
  command = plan

  variables {
    object_lock = {
      mode = "COMPLIANCE"
      days = 30
    }
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this[0].object_lock_enabled == "Enabled"
    error_message = "object lock configuration should enable Object Lock"
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].mode == "COMPLIANCE"
    error_message = "object lock should use the configured mode"
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].days == 30 && aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].years == null
    error_message = "object lock should set days and leave years unset"
  }
}

run "rejects_object_lock_bad_mode" {
  command         = plan
  expect_failures = [var.object_lock]

  variables {
    object_lock = {
      mode = "LEGAL_HOLD"
      days = 30
    }
  }
}

run "rejects_object_lock_days_and_years" {
  command         = plan
  expect_failures = [var.object_lock]

  variables {
    object_lock = {
      mode  = "GOVERNANCE"
      days  = 30
      years = 1
    }
  }
}

run "rejects_object_lock_without_period" {
  command         = plan
  expect_failures = [var.object_lock]

  variables {
    object_lock = {
      mode = "GOVERNANCE"
    }
  }
}

run "rejects_object_lock_non_positive_period" {
  command         = plan
  expect_failures = [var.object_lock]

  variables {
    object_lock = {
      mode = "GOVERNANCE"
      days = 0
    }
  }
}

run "rejects_object_lock_without_versioning" {
  command         = plan
  expect_failures = [var.object_lock]

  variables {
    versioning_enabled = false
    object_lock = {
      mode  = "GOVERNANCE"
      years = 1
    }
  }
}

###############################################################################
# Replication
###############################################################################

run "replication_creates_scoped_role" {
  command = plan

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
      storage_class          = "STANDARD_IA"
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 1 && length(aws_iam_role_policy.replication) == 1
    error_message = "replication without role_arn should create a replication role and policy"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].bucket == "arn:aws:s3:::blueprint-test-replica"
    error_message = "replication should target the configured destination bucket"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].storage_class == "STANDARD_IA"
    error_message = "replication should use the configured storage class"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].delete_marker_replication[0].status == "Disabled"
    error_message = "delete marker replication should default to Disabled"
  }

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.this[0].rule[0].source_selection_criteria) == 0
    error_message = "SSE-S3 buckets should not set source_selection_criteria"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.replication[0].statement[2].resources, "arn:aws:s3:::blueprint-test-replica/*")
    error_message = "replication policy should be scoped to the destination bucket's objects"
  }
}

run "replication_with_kms_source" {
  command = plan

  variables {
    sse_algorithm = "aws:kms"
    kms_key_arn   = "arn:aws:kms:us-east-1:111122223333:key/SOURCE"
    replication = {
      destination_bucket_arn    = "arn:aws:s3:::blueprint-test-replica"
      destination_kms_key_arn   = "arn:aws:kms:eu-west-1:111122223333:key/REPLICA"
      delete_marker_replication = true
    }
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Enabled"
    error_message = "KMS-encrypted source should opt SSE-KMS objects into replication"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].encryption_configuration[0].replica_kms_key_id == "arn:aws:kms:eu-west-1:111122223333:key/REPLICA"
    error_message = "replicas should be encrypted with the destination KMS key"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].delete_marker_replication[0].status == "Enabled"
    error_message = "delete_marker_replication = true should enable delete marker replication"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.replication[0].statement :
      s.sid == "DestinationKmsEncrypt" && contains(flatten([for c in s.condition : c.values]), "s3.eu-west-1.amazonaws.com")
    ])
    error_message = "destination KMS permission should be pinned to S3 in the destination key's region"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.replication[0].statement :
      s.sid == "SourceKmsDecrypt" && contains(s.resources, "arn:aws:kms:us-east-1:111122223333:key/SOURCE")
    ])
    error_message = "replication role should be able to decrypt with the source key"
  }
}

run "replication_with_caller_role" {
  command = plan

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
      role_arn               = "arn:aws:iam::111122223333:role/existing-replication"
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 0
    error_message = "a caller-supplied role_arn must not create a module role"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].role == "arn:aws:iam::111122223333:role/existing-replication"
    error_message = "replication should use the caller-supplied role"
  }

  assert {
    condition     = output.replication_role_arn == "arn:aws:iam::111122223333:role/existing-replication"
    error_message = "replication_role_arn should echo the caller-supplied role"
  }
}

run "rejects_replication_bad_destination" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn = "blueprint-test-replica"
    }
  }
}

run "rejects_replication_bad_storage_class" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
      storage_class          = "COLD"
    }
  }
}

run "rejects_replication_bad_kms_key" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn  = "arn:aws:s3:::blueprint-test-replica"
      destination_kms_key_arn = "alias/replica"
    }
  }
}

run "rejects_replication_bad_role" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
      role_arn               = "existing-replication"
    }
  }
}

run "rejects_replication_without_versioning" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    versioning_enabled = false
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
    }
  }
}

run "rejects_kms_replication_without_replica_key" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    sse_algorithm = "aws:kms"
    kms_key_arn   = "arn:aws:kms:us-east-1:111122223333:key/SOURCE"
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-replica"
    }
  }
}

###############################################################################
# EventBridge
###############################################################################

run "eventbridge_notifications_render" {
  command = plan

  variables {
    enable_eventbridge_notifications = true
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == true
    error_message = "enable_eventbridge_notifications should turn on EventBridge delivery"
  }
}

###############################################################################
# Intelligent-Tiering
###############################################################################

run "intelligent_tiering_renders" {
  command = plan

  variables {
    intelligent_tiering = {
      archive-all = {
        archive_access_days      = 90
        deep_archive_access_days = 180
      }
      logs = {
        prefix                   = "logs/"
        deep_archive_access_days = 365
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_intelligent_tiering_configuration.this) == 2
    error_message = "expected one intelligent-tiering configuration per map entry"
  }

  assert {
    condition     = length(aws_s3_bucket_intelligent_tiering_configuration.this["archive-all"].tiering) == 2 && length(aws_s3_bucket_intelligent_tiering_configuration.this["archive-all"].filter) == 0
    error_message = "archive-all should enable both archive tiers with no filter"
  }

  assert {
    condition     = aws_s3_bucket_intelligent_tiering_configuration.this["logs"].filter[0].prefix == "logs/"
    error_message = "logs configuration should be filtered by prefix"
  }

  assert {
    condition     = aws_s3_bucket_intelligent_tiering_configuration.this["logs"].status == "Enabled"
    error_message = "intelligent-tiering configurations should default to Enabled"
  }
}

run "rejects_intelligent_tiering_short_archive" {
  command         = plan
  expect_failures = [var.intelligent_tiering]

  variables {
    intelligent_tiering = {
      bad = {
        archive_access_days = 30
      }
    }
  }
}

run "rejects_intelligent_tiering_short_deep_archive" {
  command         = plan
  expect_failures = [var.intelligent_tiering]

  variables {
    intelligent_tiering = {
      bad = {
        deep_archive_access_days = 120
      }
    }
  }
}

run "rejects_intelligent_tiering_no_tier" {
  command         = plan
  expect_failures = [var.intelligent_tiering]

  variables {
    intelligent_tiering = {
      bad = {
        prefix = "logs/"
      }
    }
  }
}

run "rejects_intelligent_tiering_inverted_tiers" {
  command         = plan
  expect_failures = [var.intelligent_tiering]

  variables {
    intelligent_tiering = {
      bad = {
        archive_access_days      = 400
        deep_archive_access_days = 300
      }
    }
  }
}

run "rejects_intelligent_tiering_bad_name" {
  command         = plan
  expect_failures = [var.intelligent_tiering]

  variables {
    intelligent_tiering = {
      "bad name" = {
        archive_access_days = 90
      }
    }
  }
}
