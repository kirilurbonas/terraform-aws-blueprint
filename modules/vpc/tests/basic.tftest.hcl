# Plan-only tests that exercise variable wiring without contacting AWS.
# CI runs these in `terraform test -refresh=false` mode against a fake
# provider — no resources are actually created.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
}

variables {
  name_prefix        = "test"
  environment        = "dev"
  project            = "blueprint-tests"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
  nat_gateway_mode   = "single"
  enable_flow_logs   = false
}

run "defaults_plan_cleanly" {
  command = plan
}

run "module_managed_flow_logs_bucket_is_hardened" {
  command = plan

  variables {
    enable_flow_logs                     = true
    flow_logs_file_format                = "parquet"
    flow_logs_hive_compatible_partitions = true
    flow_logs_per_hour_partition         = true
  }

  assert {
    condition     = length(aws_s3_bucket_policy.flow_logs) == 1
    error_message = "module-managed flow log buckets should include a delivery policy"
  }

  assert {
    condition     = length(aws_s3_bucket_ownership_controls.flow_logs) == 1
    error_message = "module-managed flow log buckets should disable ACLs"
  }

  assert {
    condition     = aws_flow_log.this[0].destination_options[0].file_format == "parquet"
    error_message = "flow log destination options should honor the requested file format"
  }
}

run "per_az_nat_creates_per_az_routes" {
  command = plan

  variables {
    nat_gateway_mode = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == length(var.availability_zones)
    error_message = "per_az mode should create one NAT gateway per AZ"
  }
}

run "rejects_too_few_azs" {
  command         = plan
  expect_failures = [var.availability_zones]

  variables {
    availability_zones = ["us-east-1a"]
  }
}

run "rejects_bad_nat_mode" {
  command         = plan
  expect_failures = [var.nat_gateway_mode]

  variables {
    nat_gateway_mode = "double"
  }
}

run "rejects_bad_cidr" {
  command         = plan
  expect_failures = [var.vpc_cidr]

  variables {
    vpc_cidr = "not-a-cidr"
  }
}
