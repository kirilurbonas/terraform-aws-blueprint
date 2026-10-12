mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix    = "test"
  environment    = "dev"
  project        = "blueprint-tests"
  engine         = "aurora-postgresql"
  engine_version = "16.4"
  instance_class = "db.r6g.large"
  database_name  = "appdb"
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0000000000000000a",
    "subnet-0000000000000000b",
  ]
  allowed_security_groups = {
    app = "sg-0123456789abcdef0"
  }
}

run "postgres_defaults" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.cluster_identifier == "test-dev-aurora-postgresql" && aws_rds_cluster.this.port == 5432
    error_message = "cluster should follow <name_prefix>-<environment>-<engine> naming and use port 5432"
  }

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted == true && aws_rds_cluster.this.manage_master_user_password == true && aws_rds_cluster.this.master_password == null
    error_message = "storage must be encrypted and the master password RDS-managed"
  }

  assert {
    condition     = aws_rds_cluster.this.iam_database_authentication_enabled == true && aws_rds_cluster.this.deletion_protection == true && aws_rds_cluster.this.copy_tags_to_snapshot == true
    error_message = "IAM auth, deletion protection, and copy_tags_to_snapshot should default to true"
  }

  assert {
    condition     = aws_rds_cluster.this.backup_retention_period == 14 && aws_rds_cluster.this.skip_final_snapshot == true && aws_rds_cluster.this.apply_immediately == true
    error_message = "non-prod defaults: 14-day backups, no final snapshot, apply immediately"
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.this.family == "aurora-postgresql16"
    error_message = "parameter group family should be derived from engine and major version"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.exports) == 1 && aws_cloudwatch_log_group.exports["postgresql"].name == "/aws/rds/cluster/test-dev-aurora-postgresql/postgresql"
    error_message = "aurora-postgresql should manage one log group at the RDS cluster log path"
  }

  assert {
    condition     = toset(aws_rds_cluster.this.enabled_cloudwatch_logs_exports) == toset(["postgresql"])
    error_message = "aurora-postgresql should export the postgresql log by default"
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 2 && alltrue([for i in aws_rds_cluster_instance.this : i.publicly_accessible == false && i.instance_class == "db.r6g.large" && i.performance_insights_enabled == true && i.monitoring_interval == 60])
    error_message = "two private instances with PI and enhanced monitoring should be planned by default"
  }

  assert {
    condition     = length(aws_iam_role.monitoring) == 1 && length(aws_rds_cluster.this.serverlessv2_scaling_configuration) == 0
    error_message = "enhanced monitoring role expected; no serverless v2 scaling by default"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0 && length(aws_appautoscaling_target.readers) == 0
    error_message = "no alarms or reader autoscaling by default"
  }

  assert {
    condition     = aws_rds_cluster.this.tags["Module"] == "terraform-aws-blueprint/aurora" && aws_rds_cluster.this.tags["ManagedBy"] == "Terraform"
    error_message = "common tags should be applied"
  }
}

run "prod_takes_final_snapshot" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_rds_cluster.this.skip_final_snapshot == false && aws_rds_cluster.this.final_snapshot_identifier == "test-prod-aurora-postgresql-final"
    error_message = "prod should take a deterministically named final snapshot"
  }

  assert {
    condition     = aws_rds_cluster.this.apply_immediately == false && aws_rds_cluster.this.delete_automated_backups == false
    error_message = "prod should defer changes and keep automated backups"
  }
}

run "mysql_swap" {
  command = plan

  variables {
    engine           = "aurora-mysql"
    engine_version   = "8.0.mysql_aurora.3.08.0"
    backtrack_window = 86400
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.exports) == 3 && toset(keys(aws_cloudwatch_log_group.exports)) == toset(["audit", "error", "slowquery"])
    error_message = "aurora-mysql should manage audit, error, and slowquery log groups"
  }

  assert {
    condition     = aws_rds_cluster.this.port == 3306 && aws_rds_cluster.this.backtrack_window == 86400
    error_message = "aurora-mysql should use port 3306 and accept a backtrack window"
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.this.family == "aurora-mysql8.0"
    error_message = "parameter group family should be aurora-mysql8.0"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_sg["app"].from_port == 3306
    error_message = "ingress should follow the engine port"
  }
}

run "serverless_v2" {
  command = plan

  variables {
    instance_class = "db.serverless"
    serverlessv2_scaling_configuration = {
      min_capacity = 0.5
      max_capacity = 16
    }
  }

  assert {
    condition     = aws_rds_cluster.this.serverlessv2_scaling_configuration[0].min_capacity == 0.5 && aws_rds_cluster.this.serverlessv2_scaling_configuration[0].max_capacity == 16
    error_message = "serverless v2 scaling configuration should be rendered"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.instance_class == "db.serverless"])
    error_message = "instances should inherit db.serverless"
  }
}

run "instances_fan_out" {
  command = plan

  variables {
    instances = {
      writer  = { promotion_tier = 0 }
      reader1 = { promotion_tier = 1, availability_zone = "us-east-1b" }
      reader2 = { instance_class = "db.r6g.xlarge", promotion_tier = 2 }
    }
  }

  assert {
    condition     = length(aws_rds_cluster_instance.this) == 3
    error_message = "expected one cluster instance per instances entry"
  }

  assert {
    condition     = aws_rds_cluster_instance.this["reader2"].instance_class == "db.r6g.xlarge" && aws_rds_cluster_instance.this["reader1"].instance_class == "db.r6g.large"
    error_message = "per-instance instance_class should override the default"
  }

  assert {
    condition     = aws_rds_cluster_instance.this["reader1"].identifier == "test-dev-aurora-postgresql-reader1" && aws_rds_cluster_instance.this["reader1"].availability_zone == "us-east-1b" && aws_rds_cluster_instance.this["reader2"].promotion_tier == 2
    error_message = "identifier, availability_zone, and promotion_tier should be wired per instance"
  }

  assert {
    condition     = output.instance_identifiers["writer"] == "test-dev-aurora-postgresql-writer"
    error_message = "instance_identifiers should be keyed by instance key"
  }
}

run "allowed_security_groups_and_cidrs" {
  command = plan

  variables {
    allowed_security_groups = {
      eks_nodes = "sg-0fedcba9876543210"
      bastion   = "sg-00000000000000001"
    }
    allowed_cidr_blocks = ["10.0.0.0/16"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_sg) == 2 && aws_vpc_security_group_ingress_rule.from_sg["eks_nodes"].referenced_security_group_id == "sg-0fedcba9876543210"
    error_message = "expected one ingress rule per allowed_security_groups entry, keyed by label"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) == 1 && aws_vpc_security_group_ingress_rule.from_cidr["10.0.0.0/16"].from_port == 5432
    error_message = "expected one ingress rule per CIDR on the engine port"
  }
}

run "managed_secret_kms_fallback" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_rds_cluster.this.master_user_secret_kms_key_id == var.kms_key_arn && aws_rds_cluster.this.kms_key_id == var.kms_key_arn
    error_message = "storage and master secret should use kms_key_arn when no dedicated secret key is set"
  }

  assert {
    condition     = aws_rds_cluster_instance.this["one"].performance_insights_kms_key_id == var.kms_key_arn
    error_message = "Performance Insights should use kms_key_arn"
  }
}

run "managed_secret_dedicated_key" {
  command = plan

  variables {
    kms_key_arn                   = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    master_user_secret_kms_key_id = "alias/aurora-master-secret"
  }

  assert {
    condition     = aws_rds_cluster.this.master_user_secret_kms_key_id == "alias/aurora-master-secret"
    error_message = "an explicit master_user_secret_kms_key_id should win over kms_key_arn"
  }
}

run "cluster_options" {
  command = plan

  variables {
    storage_type           = "aurora-iopt1"
    enable_http_endpoint   = true
    ca_cert_identifier     = "rds-ca-rsa4096-g1"
    apply_immediately      = false
    monitoring_interval    = 0
    database_insights_mode = "advanced"

    performance_insights_retention_days = 465
    cluster_parameters = [
      { name = "log_min_duration_statement", value = "500" },
      { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
    ]
  }

  assert {
    condition     = aws_rds_cluster.this.storage_type == "aurora-iopt1" && aws_rds_cluster.this.enable_http_endpoint == true && aws_rds_cluster.this.apply_immediately == false
    error_message = "storage_type, enable_http_endpoint, and apply_immediately should be wired to the cluster"
  }

  assert {
    condition     = aws_rds_cluster.this.database_insights_mode == "advanced" && aws_rds_cluster.this.performance_insights_enabled == true && aws_rds_cluster.this.performance_insights_retention_period == 465
    error_message = "advanced Database Insights should enable cluster-level Performance Insights with the requested retention"
  }

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.this : i.ca_cert_identifier == "rds-ca-rsa4096-g1" && i.monitoring_interval == 0])
    error_message = "ca_cert_identifier and monitoring_interval should apply to every instance"
  }

  assert {
    condition     = length(aws_iam_role.monitoring) == 0
    error_message = "monitoring role should not be created when monitoring_interval = 0"
  }

  assert {
    condition     = length(aws_rds_cluster_parameter_group.this.parameter) == 4 && contains([for p in aws_rds_cluster_parameter_group.this.parameter : "${p.name}=${p.value}"], "log_min_duration_statement=500")
    error_message = "caller parameters should replace defaults of the same name and add new ones"
  }
}

run "reader_autoscaling" {
  command = plan

  variables {
    reader_autoscaling = {
      min_capacity = 1
      max_capacity = 4
      target_cpu   = 60
    }
  }

  assert {
    condition     = aws_appautoscaling_target.readers[0].min_capacity == 1 && aws_appautoscaling_target.readers[0].max_capacity == 4 && aws_appautoscaling_target.readers[0].scalable_dimension == "rds:cluster:ReadReplicaCount"
    error_message = "reader autoscaling target should bound the replica count"
  }

  assert {
    condition     = aws_appautoscaling_target.readers[0].resource_id == "cluster:test-dev-aurora-postgresql"
    error_message = "reader autoscaling should target the cluster"
  }

  assert {
    condition     = aws_appautoscaling_policy.readers_cpu[0].target_tracking_scaling_policy_configuration[0].target_value == 60
    error_message = "target_cpu should drive the target-tracking policy"
  }
}

run "cloudwatch_alarms" {
  command = plan

  variables {
    create_cloudwatch_alarms = true
    cloudwatch_alarm_thresholds = {
      cpu_utilization_percent = 90
    }
    alarm_actions = ["arn:aws:sns:us-east-1:123456789012:db-alerts"]
    ok_actions    = ["arn:aws:sns:us-east-1:123456789012:db-alerts"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 4
    error_message = "expected CPU, freeable memory, connection, and replica lag alarms"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu-utilization"].threshold == 90 && aws_cloudwatch_metric_alarm.this["freeable-memory"].threshold == 256 * 1048576
    error_message = "explicit thresholds should apply and omitted ones should take defaults"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["replica-lag"].dimensions["DBClusterIdentifier"] == "test-dev-aurora-postgresql" && aws_cloudwatch_metric_alarm.this["replica-lag"].statistic == "Maximum"
    error_message = "alarms should use the cluster dimension"
  }

  assert {
    condition     = contains(tolist(aws_cloudwatch_metric_alarm.this["database-connections"].alarm_actions), "arn:aws:sns:us-east-1:123456789012:db-alerts")
    error_message = "alarm_actions should be wired to every alarm"
  }
}

###############################################################################
# Validation / precondition failures
###############################################################################

run "rejects_bad_engine" {
  command         = plan
  expect_failures = [var.engine]

  variables {
    engine = "postgres"
  }
}

run "rejects_backtrack_on_postgres" {
  command         = plan
  expect_failures = [aws_rds_cluster.this]

  variables {
    backtrack_window = 3600
  }
}

run "rejects_backtrack_out_of_range" {
  command         = plan
  expect_failures = [var.backtrack_window]

  variables {
    engine           = "aurora-mysql"
    engine_version   = "8.0.mysql_aurora.3.08.0"
    backtrack_window = 300000
  }
}

run "rejects_min_capacity_above_max" {
  command         = plan
  expect_failures = [var.serverlessv2_scaling_configuration]

  variables {
    serverlessv2_scaling_configuration = {
      min_capacity = 8
      max_capacity = 4
    }
  }
}

run "rejects_capacity_above_256" {
  command         = plan
  expect_failures = [var.serverlessv2_scaling_configuration]

  variables {
    serverlessv2_scaling_configuration = {
      min_capacity = 1
      max_capacity = 512
    }
  }
}

run "rejects_serverless_without_scaling" {
  command         = plan
  expect_failures = [aws_rds_cluster.this]

  variables {
    instances = {
      one = { instance_class = "db.serverless" }
    }
  }
}

run "rejects_retention_out_of_range" {
  command         = plan
  expect_failures = [var.backup_retention_days]

  variables {
    backup_retention_days = 36
  }
}

run "rejects_single_subnet" {
  command         = plan
  expect_failures = [var.subnet_ids]

  variables {
    subnet_ids = ["subnet-0000000000000000a"]
  }
}

run "rejects_bad_instance_class" {
  command         = plan
  expect_failures = [var.instance_class]

  variables {
    instance_class = "r6g.large"
  }
}

run "rejects_empty_instances" {
  command         = plan
  expect_failures = [var.instances]

  variables {
    instances = {}
  }
}

run "rejects_bad_promotion_tier" {
  command         = plan
  expect_failures = [var.instances]

  variables {
    instances = {
      one = { promotion_tier = 16 }
    }
  }
}

run "rejects_mysql_log_type_on_postgres" {
  command         = plan
  expect_failures = [aws_rds_cluster.this]

  variables {
    enabled_cloudwatch_logs_exports = ["slowquery"]
  }
}

run "rejects_unknown_log_type" {
  command         = plan
  expect_failures = [var.enabled_cloudwatch_logs_exports]

  variables {
    enabled_cloudwatch_logs_exports = ["upgrade"]
  }
}

run "rejects_advanced_insights_with_short_retention" {
  command         = plan
  expect_failures = [aws_rds_cluster.this]

  variables {
    database_insights_mode = "advanced"
  }
}

run "rejects_bad_storage_type" {
  command         = plan
  expect_failures = [var.storage_type]

  variables {
    storage_type = "gp3"
  }
}

run "rejects_bad_reader_autoscaling" {
  command         = plan
  expect_failures = [var.reader_autoscaling]

  variables {
    reader_autoscaling = {
      min_capacity = 5
      max_capacity = 2
    }
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

run "rejects_bad_cidr" {
  command         = plan
  expect_failures = [var.allowed_cidr_blocks]

  variables {
    allowed_cidr_blocks = ["10.0.0.0/33"]
  }
}

run "rejects_bad_alarm_thresholds" {
  command         = plan
  expect_failures = [var.cloudwatch_alarm_thresholds]

  variables {
    cloudwatch_alarm_thresholds = {
      cpu_utilization_percent = 150
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

run "rejects_bad_master_user_secret_kms_key_id" {
  command         = plan
  expect_failures = [var.master_user_secret_kms_key_id]

  variables {
    master_user_secret_kms_key_id = "not-a-key"
  }
}

run "rejects_duplicate_cluster_parameters" {
  command         = plan
  expect_failures = [var.cluster_parameters]

  variables {
    cluster_parameters = [
      { name = "log_connections", value = "1" },
      { name = "log_connections", value = "0" },
    ]
  }
}
