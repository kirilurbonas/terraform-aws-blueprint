terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/aurora"
    },
    var.tags,
  )

  name_prefix = "${var.name_prefix}-${var.environment}"
  identifier  = "${local.name_prefix}-${var.engine}"
  is_postgres = var.engine == "aurora-postgresql"
  is_mysql    = var.engine == "aurora-mysql"
  is_prod     = var.environment == "prod"
  port        = local.is_postgres ? 5432 : 3306

  # aurora-postgresql16 from "16.4"; aurora-mysql8.0 from "8.0.mysql_aurora.3.05.2".
  family = var.parameter_group_family != null ? var.parameter_group_family : (
    local.is_postgres ? "aurora-postgresql${split(".", var.engine_version)[0]}" : "aurora-mysql${join(".", slice(split(".", var.engine_version), 0, 2))}"
  )

  default_log_exports = local.is_postgres ? ["postgresql"] : ["audit", "error", "slowquery"]
  log_exports         = var.enabled_cloudwatch_logs_exports != null ? var.enabled_cloudwatch_logs_exports : local.default_log_exports
  valid_log_exports   = local.is_postgres ? ["postgresql", "iam-db-auth-error"] : ["audit", "error", "general", "slowquery", "iam-db-auth-error"]

  # The RDS-managed secret falls back to the module-wide CMK when no dedicated
  # key is given; both null means the AWS-managed aws/secretsmanager key.
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id != null ? var.master_user_secret_kms_key_id : var.kms_key_arn

  # Null: apply immediately outside prod, defer to the maintenance window in prod.
  apply_immediately = var.apply_immediately != null ? var.apply_immediately : !local.is_prod

  # Engine defaults. audit log export on aurora-mysql only receives data when
  # server_audit_logging is on, so the defaults enable it.
  default_params = local.is_postgres ? [
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" },
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    ] : [
    { name = "slow_query_log", value = "1", apply_method = "immediate" },
    { name = "long_query_time", value = "1", apply_method = "immediate" },
    { name = "log_output", value = "FILE", apply_method = "immediate" },
    { name = "server_audit_logging", value = "1", apply_method = "immediate" },
    { name = "server_audit_events", value = "CONNECT,QUERY_DCL,QUERY_DDL", apply_method = "immediate" },
  ]

  # Caller-supplied parameters replace engine defaults of the same name.
  cluster_parameters = merge(
    { for p in local.default_params : p.name => p },
    { for p in var.cluster_parameters : p.name => p },
  )

  instance_classes = {
    for key, inst in var.instances : key => coalesce(inst.instance_class, var.instance_class)
  }
  uses_serverless = contains(values(local.instance_classes), "db.serverless")
}

###############################################################################
# Subnet group + security group
###############################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${local.identifier}-"
  description = "Subnet group for Aurora cluster ${local.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name_prefix = "${local.identifier}-"
  description = "Security group for Aurora cluster ${local.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "DB ingress from caller-provided CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-ingress-cidr"
  })
}

# for_each keys are caller-chosen static labels, so SG IDs that are only known
# after apply (e.g. created in the same run) are accepted.
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "DB ingress from caller-provided SG ${each.key}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-ingress-sg-${each.key}"
  })
}

###############################################################################
# Cluster parameter group
###############################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${local.identifier}-"
  family      = local.family
  description = "Cluster parameter group for Aurora cluster ${local.identifier}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-cluster-pg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Monitoring role for Enhanced Monitoring (optional)
###############################################################################

data "aws_iam_policy_document" "monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${substr(local.identifier, 0, 32)}-mon-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role[0].json

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

###############################################################################
# Exported log groups
#
# Created before the cluster so RDS writes into module-managed groups with a
# retention policy instead of auto-creating never-expiring ones.
###############################################################################

resource "aws_cloudwatch_log_group" "exports" {
  for_each = toset(local.log_exports)

  name              = "/aws/rds/cluster/${local.identifier}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = merge(local.common_tags, {
    Name      = "${local.identifier}-${each.value}-logs"
    LogType   = each.value
    DBCluster = local.identifier
  })
}

###############################################################################
# Aurora cluster
###############################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier = local.identifier

  engine         = var.engine
  engine_mode    = "provisioned"
  engine_version = var.engine_version

  database_name   = var.database_name
  master_username = var.master_username
  port            = local.port

  # RDS generates and rotates the password in its own Secrets Manager secret;
  # the plaintext never enters Terraform state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.master_user_secret_kms_key_id

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn
  storage_type      = var.storage_type

  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  enable_http_endpoint                = var.enable_http_endpoint

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  delete_automated_backups     = !local.is_prod
  backtrack_window             = local.is_mysql ? var.backtrack_window : null

  # Deterministic ID prevents the timestamp()-induced perpetual diff.
  # The snapshot is only consulted when the cluster is actually destroyed.
  skip_final_snapshot       = !local.is_prod
  final_snapshot_identifier = local.is_prod ? "${local.identifier}-final" : null
  deletion_protection       = var.deletion_protection

  # Advanced Database Insights is a cluster-level setting and requires
  # cluster-level Performance Insights with at least 465 days of retention.
  database_insights_mode                = var.database_insights_mode
  performance_insights_enabled          = var.database_insights_mode == "advanced" ? true : null
  performance_insights_retention_period = var.database_insights_mode == "advanced" ? var.performance_insights_retention_days : null
  performance_insights_kms_key_id       = var.database_insights_mode == "advanced" ? var.kms_key_arn : null

  enabled_cloudwatch_logs_exports = local.log_exports

  apply_immediately = local.apply_immediately

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      min_capacity             = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity             = serverlessv2_scaling_configuration.value.max_capacity
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.seconds_until_auto_pause
    }
  }

  tags = merge(local.common_tags, {
    Name = local.identifier
  })

  lifecycle {
    precondition {
      condition     = var.backtrack_window == 0 || local.is_mysql
      error_message = "backtrack_window is only supported by aurora-mysql; leave it at 0 for aurora-postgresql."
    }

    precondition {
      condition     = alltrue([for t in local.log_exports : contains(local.valid_log_exports, t)])
      error_message = "enabled_cloudwatch_logs_exports contains a log type the engine does not support. aurora-postgresql: postgresql, iam-db-auth-error. aurora-mysql: audit, error, general, slowquery, iam-db-auth-error."
    }

    precondition {
      condition     = !local.uses_serverless || var.serverlessv2_scaling_configuration != null
      error_message = "serverlessv2_scaling_configuration must be set when any instance uses instance_class = \"db.serverless\"."
    }

    precondition {
      condition     = var.database_insights_mode != "advanced" || (var.performance_insights_enabled && var.performance_insights_retention_days >= 465)
      error_message = "database_insights_mode = \"advanced\" requires performance_insights_enabled = true and performance_insights_retention_days >= 465."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.exports,
  ]
}

###############################################################################
# Cluster instances
###############################################################################

resource "aws_rds_cluster_instance" "this" {
  for_each = var.instances

  identifier         = "${local.identifier}-${each.key}"
  cluster_identifier = aws_rds_cluster.this.id

  engine         = aws_rds_cluster.this.engine
  engine_version = aws_rds_cluster.this.engine_version
  instance_class = local.instance_classes[each.key]

  promotion_tier    = each.value.promotion_tier
  availability_zone = each.value.availability_zone

  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  ca_cert_identifier   = var.ca_cert_identifier

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  copy_tags_to_snapshot      = true
  apply_immediately          = local.apply_immediately

  tags = merge(local.common_tags, {
    Name     = "${local.identifier}-${each.key}"
    Instance = each.key
  })

  depends_on = [
    aws_iam_role_policy_attachment.monitoring,
  ]
}

###############################################################################
# Reader autoscaling (optional)
#
# Application Auto Scaling adds and removes Aurora Replicas outside Terraform.
# Those replicas are not in state and take the writer's instance class.
###############################################################################

resource "aws_appautoscaling_target" "readers" {
  count = var.reader_autoscaling != null ? 1 : 0

  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  min_capacity       = var.reader_autoscaling.min_capacity
  max_capacity       = var.reader_autoscaling.max_capacity

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-readers"
  })

  depends_on = [aws_rds_cluster_instance.this]
}

resource "aws_appautoscaling_policy" "readers_cpu" {
  count = var.reader_autoscaling != null ? 1 : 0

  name               = "${local.identifier}-readers-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.readers[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.readers[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.readers[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.reader_autoscaling.target_cpu
    scale_in_cooldown  = var.reader_autoscaling.scale_in_cooldown
    scale_out_cooldown = var.reader_autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
  }
}

###############################################################################
# CloudWatch alarms (optional)
#
# Cluster-level metrics (DBClusterIdentifier dimension). Memory is taken in MiB
# and converted to the bytes the AWS/RDS metric reports.
###############################################################################

locals {
  cloudwatch_alarms = var.create_cloudwatch_alarms ? {
    cpu-utilization = {
      metric_name         = "CPUUtilization"
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Average"
      threshold           = var.cloudwatch_alarm_thresholds.cpu_utilization_percent
      description         = "Average CPU utilization of ${local.identifier} is above ${var.cloudwatch_alarm_thresholds.cpu_utilization_percent}%."
    }
    freeable-memory = {
      metric_name         = "FreeableMemory"
      comparison_operator = "LessThanThreshold"
      statistic           = "Average"
      threshold           = var.cloudwatch_alarm_thresholds.freeable_memory_mb * 1048576
      description         = "Freeable memory on ${local.identifier} is below ${var.cloudwatch_alarm_thresholds.freeable_memory_mb} MiB."
    }
    database-connections = {
      metric_name         = "DatabaseConnections"
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Average"
      threshold           = var.cloudwatch_alarm_thresholds.database_connections
      description         = "Open connections on ${local.identifier} are above ${var.cloudwatch_alarm_thresholds.database_connections}."
    }
    replica-lag = {
      metric_name         = "AuroraReplicaLagMaximum"
      comparison_operator = "GreaterThanThreshold"
      statistic           = "Maximum"
      threshold           = var.cloudwatch_alarm_thresholds.replica_lag_ms
      description         = "Maximum Aurora Replica lag on ${local.identifier} is above ${var.cloudwatch_alarm_thresholds.replica_lag_ms} ms."
    }
  } : {}
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.cloudwatch_alarms

  alarm_name          = "${local.identifier}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = var.cloudwatch_alarm_thresholds.period_seconds
  evaluation_periods  = var.cloudwatch_alarm_thresholds.evaluation_periods
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-${each.key}"
  })
}
