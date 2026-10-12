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

run "module_managed_password_is_default" {
  command = plan

  assert {
    condition     = length(random_password.master) == 1 && length(aws_secretsmanager_secret.master) == 1
    error_message = "default mode should generate the password and store it in a module-managed secret"
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == null
    error_message = "manage_master_user_password must stay unset by default"
  }

  assert {
    condition     = output.master_user_secret_arn == null
    error_message = "master_user_secret_arn should be null outside managed mode"
  }

  assert {
    condition     = aws_db_instance.this.apply_immediately == true && aws_db_instance.this.copy_tags_to_snapshot == true
    error_message = "non-prod defaults should keep apply_immediately = true and copy_tags_to_snapshot = true"
  }

  assert {
    condition     = length(aws_db_instance.this.blue_green_update) == 0 && aws_db_instance.this.iam_database_authentication_enabled == false
    error_message = "blue/green and IAM auth must stay off by default"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "no alarms should be created by default"
  }
}

run "prod_defers_changes_to_maintenance_window" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_db_instance.this.apply_immediately == false
    error_message = "prod should keep deferring changes to the maintenance window when apply_immediately is null"
  }
}

run "rds_managed_master_password" {
  command = plan

  variables {
    manage_master_password = true
    kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    read_replicas = {
      ro1 = {}
    }
  }

  assert {
    condition     = length(random_password.master) == 0 && length(aws_secretsmanager_secret.master) == 0 && length(aws_secretsmanager_secret_version.master) == 0
    error_message = "managed mode must not create random_password or a module-managed secret"
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true && aws_db_instance.this.password == null
    error_message = "managed mode should enable manage_master_user_password and pass no password"
  }

  assert {
    condition     = aws_db_instance.this.master_user_secret_kms_key_id == var.kms_key_arn
    error_message = "master_user_secret_kms_key_id should fall back to kms_key_arn"
  }

  assert {
    condition     = output.master_password == null && output.master_secret_arn == null
    error_message = "module-managed password outputs should be null in managed mode"
  }

  assert {
    condition     = length(aws_db_instance.replica) == 1
    error_message = "read replicas should still plan in managed mode"
  }
}

run "rds_managed_master_password_dedicated_key" {
  command = plan

  variables {
    manage_master_password        = true
    kms_key_arn                   = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    master_user_secret_kms_key_id = "alias/rds-master-secret"
  }

  assert {
    condition     = aws_db_instance.this.master_user_secret_kms_key_id == "alias/rds-master-secret"
    error_message = "an explicit master_user_secret_kms_key_id should win over kms_key_arn"
  }
}

run "instance_hardening_inputs" {
  command = plan

  variables {
    ca_cert_identifier                  = "rds-ca-rsa4096-g1"
    copy_tags_to_snapshot               = false
    iam_database_authentication_enabled = true
    apply_immediately                   = false
    blue_green_update                   = true
    read_replicas = {
      ro1 = {}
    }
  }

  assert {
    condition     = aws_db_instance.this.ca_cert_identifier == "rds-ca-rsa4096-g1" && aws_db_instance.replica["ro1"].ca_cert_identifier == "rds-ca-rsa4096-g1"
    error_message = "ca_cert_identifier should be applied to the primary and replicas"
  }

  assert {
    condition     = aws_db_instance.this.copy_tags_to_snapshot == false
    error_message = "copy_tags_to_snapshot should be wired to the primary"
  }

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled == true && aws_db_instance.replica["ro1"].iam_database_authentication_enabled == true
    error_message = "IAM database authentication should be enabled on the primary and replicas"
  }

  assert {
    condition     = aws_db_instance.this.apply_immediately == false && aws_db_instance.replica["ro1"].apply_immediately == false
    error_message = "an explicit apply_immediately should override the environment-based default"
  }

  assert {
    condition     = aws_db_instance.this.blue_green_update[0].enabled == true
    error_message = "blue_green_update should render an enabled blue_green_update block"
  }
}

run "cloudwatch_alarms" {
  command = plan

  variables {
    create_cloudwatch_alarms = true
    cloudwatch_alarm_thresholds = {
      cpu_utilization_percent = 90
      free_storage_space_gb   = 20
    }
    alarm_actions = ["arn:aws:sns:us-east-1:123456789012:rds-alerts"]
    ok_actions    = ["arn:aws:sns:us-east-1:123456789012:rds-alerts"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 4
    error_message = "expected CPU, free storage, freeable memory, and connection alarms"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu-utilization"].threshold == 90 && aws_cloudwatch_metric_alarm.this["database-connections"].threshold == 100
    error_message = "explicit thresholds should apply and omitted ones should take defaults"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["free-storage-space"].threshold == 20 * 1073741824
    error_message = "free_storage_space_gb should be converted to bytes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu-utilization"].alarm_name == "test-dev-postgres-cpu-utilization"
    error_message = "alarm names should follow the <name_prefix>-<environment>-<engine>-<metric> convention"
  }

  assert {
    condition     = contains(tolist(aws_cloudwatch_metric_alarm.this["freeable-memory"].alarm_actions), "arn:aws:sns:us-east-1:123456789012:rds-alerts")
    error_message = "alarm_actions should be wired to every alarm"
  }
}

run "rejects_bad_master_user_secret_kms_key_id" {
  command         = plan
  expect_failures = [var.master_user_secret_kms_key_id]

  variables {
    manage_master_password        = true
    master_user_secret_kms_key_id = "not-a-key"
  }
}

run "rejects_bad_ca_cert_identifier" {
  command         = plan
  expect_failures = [var.ca_cert_identifier]

  variables {
    ca_cert_identifier = "rsa2048"
  }
}

run "rejects_bad_cpu_threshold" {
  command         = plan
  expect_failures = [var.cloudwatch_alarm_thresholds]

  variables {
    cloudwatch_alarm_thresholds = {
      cpu_utilization_percent = 150
    }
  }
}

run "rejects_non_positive_thresholds" {
  command         = plan
  expect_failures = [var.cloudwatch_alarm_thresholds]

  variables {
    cloudwatch_alarm_thresholds = {
      free_storage_space_gb = 0
    }
  }
}

run "rejects_bad_alarm_period" {
  command         = plan
  expect_failures = [var.cloudwatch_alarm_thresholds]

  variables {
    cloudwatch_alarm_thresholds = {
      period_seconds = 45
    }
  }
}

run "rejects_bad_evaluation_periods" {
  command         = plan
  expect_failures = [var.cloudwatch_alarm_thresholds]

  variables {
    cloudwatch_alarm_thresholds = {
      evaluation_periods = 0
    }
  }
}

run "rejects_non_sns_alarm_action" {
  command         = plan
  expect_failures = [var.alarm_actions]

  variables {
    alarm_actions = ["arn:aws:lambda:us-east-1:123456789012:function:notify"]
  }
}

run "rejects_non_sns_ok_action" {
  command         = plan
  expect_failures = [var.ok_actions]

  variables {
    ok_actions = ["rds-alerts"]
  }
}

run "allowed_security_groups_map" {
  command = plan

  variables {
    allowed_security_groups = {
      eks_nodes = "sg-0fedcba9876543210"
      bastion   = "sg-00000000000000001"
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_sg_map) == 2
    error_message = "expected one ingress rule per allowed_security_groups entry"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_sg_map["eks_nodes"].referenced_security_group_id == "sg-0fedcba9876543210"
    error_message = "map-form rules should reference the given SG ID under its label"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_sg) == 1
    error_message = "list-form rules should be unaffected by the map form"
  }
}

run "rejects_non_sg_allowed_security_group" {
  command         = plan
  expect_failures = [var.allowed_security_groups]

  variables {
    allowed_security_groups = {
      eks_nodes = "vpc-0123456789abcdef0"
    }
  }
}
