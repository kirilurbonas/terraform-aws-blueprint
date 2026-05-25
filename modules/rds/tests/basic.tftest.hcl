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

run "mysql_swap" {
  command = plan

  variables {
    engine         = "mysql"
    engine_version = "8.0.36"
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
