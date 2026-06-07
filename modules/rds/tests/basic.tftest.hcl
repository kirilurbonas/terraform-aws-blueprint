mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

variables {
  name_prefix    = "test"
  environment    = "dev"
  project        = "blueprint-tests"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.m6i.large"
  db_name        = "appdb"
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0000000000000000a",
    "subnet-0000000000000000b",
  ]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
}

run "postgres_defaults_plan_cleanly" {
  command = plan
}

run "postgres_log_groups_are_managed" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.exports) == 2
    error_message = "postgres deployments should manage two CloudWatch log groups"
  }
}

run "mysql_swap" {
  command = plan

  variables {
    engine         = "mysql"
    engine_version = "8.0.36"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.exports) == 4
    error_message = "mysql deployments should manage four CloudWatch log groups"
  }
}

run "replicas_fan_out" {
  command = plan

  variables {
    read_replicas = {
      ro1 = { instance_class = "db.m6i.large" }
      ro2 = { instance_class = "db.m6i.large", multi_az = true }
    }
  }

  assert {
    condition     = length(aws_db_instance.replica) == 2
    error_message = "expected one replica instance per read_replicas entry"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.exports) == 6
    error_message = "primary plus two replicas should each receive managed log groups"
  }
}

run "rejects_bad_engine" {
  command         = plan
  expect_failures = [var.engine]

  variables {
    engine = "oracle"
  }
}

run "rejects_bad_instance_class" {
  command         = plan
  expect_failures = [var.instance_class]

  variables {
    instance_class = "m6i.large"
  }
}

run "rejects_storage_autoscaling_below_allocated" {
  command         = plan
  expect_failures = [var.max_allocated_storage_gb]

  variables {
    allocated_storage_gb     = 200
    max_allocated_storage_gb = 100
  }
}
