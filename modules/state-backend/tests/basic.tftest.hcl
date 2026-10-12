mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  environment     = "dev"
  project         = "blueprint-tests"
  bucket_name     = "blueprint-test-tfstate-111122223333"
  lock_table_name = "blueprint-test-tfstate-locks"
}

run "defaults_plan_cleanly" {
  command = plan
}

run "rejects_bad_bucket" {
  command         = plan
  expect_failures = [var.bucket_name]

  variables {
    bucket_name = "Bad_Bucket_Name"
  }
}

###############################################################################
# Locking
###############################################################################

run "dynamodb_lock_default_unchanged" {
  command = plan

  # The bucket ID is computed; pin it so the rendered HCL can be compared whole.
  override_resource {
    target          = aws_s3_bucket.state
    override_during = plan
    values = {
      id  = "blueprint-test-tfstate-111122223333"
      arn = "arn:aws:s3:::blueprint-test-tfstate-111122223333"
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.lock) == 1 && aws_dynamodb_table.lock[0].name == "blueprint-test-tfstate-locks"
    error_message = "the DynamoDB lock table should be created by default"
  }

  assert {
    condition     = output.lock_table_name == "blueprint-test-tfstate-locks"
    error_message = "lock_table_name should be the configured table name by default"
  }

  assert {
    condition     = length(regexall("dynamodb_table = \"blueprint-test-tfstate-locks\"", output.backend_config_hcl)) == 1 && !strcontains(output.backend_config_hcl, "use_lockfile")
    error_message = "default backend_config_hcl should use dynamodb_table and not use_lockfile"
  }

  assert {
    condition     = output.backend_config_hcl == <<-EOT
      bucket         = "blueprint-test-tfstate-111122223333"
      key            = "<stack-name>/terraform.tfstate"
      region         = "us-east-1"
      dynamodb_table = "blueprint-test-tfstate-locks"
      encrypt        = true
    EOT
    error_message = "default backend_config_hcl must be unchanged from previous releases"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.state) == 0 && length(aws_s3_bucket_replication_configuration.state) == 0 && length(aws_iam_role.replication) == 0
    error_message = "access logging and replication must be off by default"
  }

  assert {
    condition     = output.replication_role_arn == null
    error_message = "replication_role_arn should be null when replication is disabled"
  }
}

run "s3_native_locking" {
  command = plan

  # The bucket ID is computed; pin it so the rendered HCL can be compared whole.
  override_resource {
    target          = aws_s3_bucket.state
    override_during = plan
    values = {
      id  = "blueprint-test-tfstate-111122223333"
      arn = "arn:aws:s3:::blueprint-test-tfstate-111122223333"
    }
  }

  variables {
    enable_dynamodb_lock = false
    lock_table_name      = null
  }

  assert {
    condition     = length(aws_dynamodb_table.lock) == 0
    error_message = "no lock table should be created when enable_dynamodb_lock = false"
  }

  assert {
    condition     = output.lock_table_name == null && output.lock_table_arn == null
    error_message = "lock table outputs should be null when enable_dynamodb_lock = false"
  }

  assert {
    condition     = output.backend_config_hcl == <<-EOT
      bucket       = "blueprint-test-tfstate-111122223333"
      key          = "<stack-name>/terraform.tfstate"
      region       = "us-east-1"
      use_lockfile = true
      encrypt      = true
    EOT
    error_message = "backend_config_hcl should emit use_lockfile = true and no dynamodb_table"
  }
}

run "rejects_dynamodb_lock_without_table_name" {
  command         = plan
  expect_failures = [var.lock_table_name]

  variables {
    lock_table_name = null
  }
}

run "rejects_bad_lock_table_name" {
  command         = plan
  expect_failures = [var.lock_table_name]

  variables {
    lock_table_name = "x"
  }
}

###############################################################################
# Access logging
###############################################################################

run "access_logging_renders" {
  command = plan

  # The bucket ID is computed; pin it so the rendered HCL can be compared whole.
  override_resource {
    target          = aws_s3_bucket.state
    override_during = plan
    values = {
      id  = "blueprint-test-tfstate-111122223333"
      arn = "arn:aws:s3:::blueprint-test-tfstate-111122223333"
    }
  }

  variables {
    access_logging = {
      target_bucket = "blueprint-test-access-logs"
    }
  }

  assert {
    condition     = aws_s3_bucket_logging.state[0].target_bucket == "blueprint-test-access-logs"
    error_message = "access logging should target the configured bucket"
  }

  assert {
    condition     = aws_s3_bucket_logging.state[0].target_prefix == "blueprint-test-tfstate-111122223333/"
    error_message = "access logging prefix should default to <bucket_name>/"
  }
}

run "rejects_access_logging_bad_target" {
  command         = plan
  expect_failures = [var.access_logging]

  variables {
    access_logging = {
      target_bucket = "Bad_Bucket"
    }
  }
}

run "rejects_access_logging_to_self" {
  command         = plan
  expect_failures = [var.access_logging]

  variables {
    access_logging = {
      target_bucket = "blueprint-test-tfstate-111122223333"
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
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-tfstate-dr"
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 1 && length(aws_iam_role_policy.replication) == 1
    error_message = "replication without role_arn should create a replication role and policy"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.state[0].rule[0].destination[0].bucket == "arn:aws:s3:::blueprint-test-tfstate-dr"
    error_message = "replication should target the configured DR bucket"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.state[0].rule[0].delete_marker_replication[0].status == "Disabled"
    error_message = "state replication must not propagate delete markers"
  }

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.state[0].rule[0].source_selection_criteria) == 0
    error_message = "SSE-S3 state bucket should not set source_selection_criteria"
  }
}

run "replication_with_kms" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/SOURCE"
    replication = {
      destination_bucket_arn  = "arn:aws:s3:::blueprint-test-tfstate-dr"
      destination_kms_key_arn = "arn:aws:kms:us-west-2:111122223333:key/REPLICA"
    }
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.state[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Enabled"
    error_message = "KMS-encrypted state should opt SSE-KMS objects into replication"
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.state[0].rule[0].destination[0].encryption_configuration[0].replica_kms_key_id == "arn:aws:kms:us-west-2:111122223333:key/REPLICA"
    error_message = "replicas should be encrypted with the destination KMS key"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.replication[0].statement :
      s.sid == "SourceKmsDecrypt" && contains(flatten([for c in s.condition : c.values]), "s3.us-east-1.amazonaws.com")
    ])
    error_message = "source KMS permission should be pinned to S3 in the bucket's region"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.replication[0].statement :
      s.sid == "DestinationKmsEncrypt" && contains(flatten([for c in s.condition : c.values]), "s3.us-west-2.amazonaws.com")
    ])
    error_message = "destination KMS permission should be pinned to S3 in the destination key's region"
  }
}

run "replication_with_caller_role" {
  command = plan

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-tfstate-dr"
      role_arn               = "arn:aws:iam::111122223333:role/existing-replication"
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 0 && aws_s3_bucket_replication_configuration.state[0].role == "arn:aws:iam::111122223333:role/existing-replication"
    error_message = "a caller-supplied role_arn should be used without creating a module role"
  }
}

run "rejects_replication_bad_destination" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn = "blueprint-test-tfstate-dr"
    }
  }
}

run "rejects_replication_bad_kms_key" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn  = "arn:aws:s3:::blueprint-test-tfstate-dr"
      destination_kms_key_arn = "alias/replica"
    }
  }
}

run "rejects_replication_bad_role" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-tfstate-dr"
      role_arn               = "existing-replication"
    }
  }
}

run "rejects_kms_replication_without_replica_key" {
  command         = plan
  expect_failures = [var.replication]

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/SOURCE"
    replication = {
      destination_bucket_arn = "arn:aws:s3:::blueprint-test-tfstate-dr"
    }
  }
}
