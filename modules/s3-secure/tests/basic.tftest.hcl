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
}

run "rejects_bad_sse" {
  command         = plan
  expect_failures = [var.sse_algorithm]

  variables {
    sse_algorithm = "DES"
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
