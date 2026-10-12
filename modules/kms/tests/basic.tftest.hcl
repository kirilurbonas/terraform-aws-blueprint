mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  environment = "dev"
  project     = "blueprint-tests"
  alias       = "blueprint-test-app"
}

run "defaults_plan_cleanly" {
  command = plan

  assert {
    condition     = length(aws_kms_replica_key.this) == 0 && length(aws_kms_alias.replica) == 0
    error_message = "replicas should be opt-in"
  }
  assert {
    condition     = output.replica_key_arns == {}
    error_message = "replica_key_arns should be empty without replicas"
  }
}

run "rejects_bad_window" {
  command         = plan
  expect_failures = [var.deletion_window_in_days]

  variables {
    deletion_window_in_days = 3
  }
}

run "rejects_bad_env" {
  command         = plan
  expect_failures = [var.environment]

  variables {
    environment = "qa"
  }
}

run "rotation_period_is_wired" {
  command = plan

  variables {
    rotation_period_in_days = 180
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 180
    error_message = "rotation_period_in_days should be passed to the key"
  }
}

run "rejects_short_rotation_period" {
  command         = plan
  expect_failures = [var.rotation_period_in_days]

  variables {
    rotation_period_in_days = 30
  }
}

run "rejects_long_rotation_period" {
  command         = plan
  expect_failures = [var.rotation_period_in_days]

  variables {
    rotation_period_in_days = 3000
  }
}

run "replicas_per_region" {
  command = plan

  variables {
    multi_region            = true
    replica_regions         = ["eu-west-1", "ap-southeast-2"]
    deletion_window_in_days = 14
  }

  assert {
    condition     = aws_kms_key.this.multi_region
    error_message = "the primary key should be multi-Region"
  }
  assert {
    condition     = toset(keys(aws_kms_replica_key.this)) == toset(["eu-west-1", "ap-southeast-2"])
    error_message = "expected one replica per requested region"
  }
  assert {
    condition = alltrue([
      for r, k in aws_kms_replica_key.this :
      k.region == r && k.deletion_window_in_days == 14 && k.policy == data.aws_iam_policy_document.key.json && k.tags["Name"] == "blueprint-test-app"
    ])
    error_message = "replicas should be placed in their region with the primary's deletion window, policy and tags"
  }
  assert {
    condition = alltrue([
      for r, a in aws_kms_alias.replica : a.region == r && a.name == "alias/blueprint-test-app"
    ])
    error_message = "each replica should get the same alias in its own region"
  }
  assert {
    condition     = toset(keys(output.replica_key_arns)) == toset(["eu-west-1", "ap-southeast-2"])
    error_message = "replica_key_arns should be keyed by region"
  }
}

run "rejects_replicas_without_multi_region" {
  command         = plan
  expect_failures = [aws_kms_key.this]

  variables {
    replica_regions = ["eu-west-1"]
  }
}

run "rejects_replica_in_primary_region" {
  command         = plan
  expect_failures = [aws_kms_replica_key.this]

  variables {
    multi_region    = true
    replica_regions = ["us-east-1"]
  }
}

run "rejects_bad_replica_region" {
  command         = plan
  expect_failures = [var.replica_regions]

  variables {
    multi_region    = true
    replica_regions = ["Europe"]
  }
}
