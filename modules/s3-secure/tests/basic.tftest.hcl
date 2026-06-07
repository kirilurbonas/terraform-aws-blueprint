mock_provider "aws" {}

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
