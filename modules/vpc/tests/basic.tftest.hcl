# Plan-only tests that exercise variable wiring without contacting AWS.
# CI runs these in `terraform test -refresh=false` mode against a fake
# provider — no resources are actually created.

mock_provider "aws" {}

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
