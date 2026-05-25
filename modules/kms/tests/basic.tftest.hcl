mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
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
