terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5, < 4.0"
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
      Module      = "terraform-aws-blueprint/rds"
    },
    var.tags,
  )

  name_prefix    = "${var.name_prefix}-${var.environment}"
  identifier     = "${local.name_prefix}-${var.engine}"
  is_postgres    = var.engine == "postgres"
  port           = var.port != null ? var.port : (local.is_postgres ? 5432 : 3306)
  family         = var.parameter_group_family != null ? var.parameter_group_family : (local.is_postgres ? "postgres${split(".", var.engine_version)[0]}" : "mysql${join(".", slice(split(".", var.engine_version), 0, 2))}")
  is_prod        = var.environment == "prod"
  db_log_exports = local.is_postgres ? ["postgresql", "upgrade"] : ["audit", "error", "general", "slowquery"]

  # In managed mode RDS generates and rotates the password in its own Secrets
  # Manager secret, so the module never sees (or stores) the plaintext.
  master_secret = var.manage_master_password ? null : random_password.master[0].result

  # The RDS-managed secret falls back to the module-wide CMK when no dedicated
  # key is given; both null means the AWS-managed aws/secretsmanager key.
  master_user_secret_kms_key_id = var.manage_master_password ? (
    var.master_user_secret_kms_key_id != null ? var.master_user_secret_kms_key_id : var.kms_key_arn
  ) : null

  # Null keeps the historical behaviour: apply immediately outside prod, defer
  # to the maintenance window in prod.
  apply_immediately = var.apply_immediately != null ? var.apply_immediately : !local.is_prod

  default_params = local.is_postgres ? [
    { name = "log_min_duration_statement", value = "1000" },
    { name = "log_connections", value = "1" },
    { name = "log_disconnections", value = "1" },
    ] : [
    { name = "slow_query_log", value = "1" },
    { name = "long_query_time", value = "1" },
    { name = "log_output", value = "FILE" },
  ]

  db_log_group_items = concat(
    [
      for log_type in local.db_log_exports : {
        key        = "primary:${log_type}"
        identifier = local.identifier
        log_type   = log_type
      }
    ],
    flatten([
      for replica_key, _ in var.read_replicas : [
        for log_type in local.db_log_exports : {
          key        = "${replica_key}:${log_type}"
          identifier = "${local.identifier}-replica-${replica_key}"
          log_type   = log_type
        }
      ]
    ]),
  )

  db_log_groups = {
    for item in local.db_log_group_items : item.key => item
  }
}

###############################################################################
# Master password (stored in Secrets Manager)
#
# Only created when manage_master_password = false. The moved blocks keep
# existing state addresses stable now that these resources carry a count.
###############################################################################

moved {
  from = random_password.master
  to   = random_password.master[0]
}

moved {
  from = aws_secretsmanager_secret.master
  to   = aws_secretsmanager_secret.master[0]
}

moved {
  from = aws_secretsmanager_secret_version.master
  to   = aws_secretsmanager_secret_version.master[0]
}

resource "random_password" "master" {
  count = var.manage_master_password ? 0 : 1

  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "master" {
  count = var.manage_master_password ? 0 : 1

  name_prefix             = "${local.identifier}-master-"
  description             = "Master credentials for RDS ${local.identifier}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = local.is_prod ? 30 : 0

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-master-secret"
  })
}

resource "aws_secretsmanager_secret_version" "master" {
  count = var.manage_master_password ? 0 : 1

  secret_id = aws_secretsmanager_secret.master[0].id
  secret_string = jsonencode({
    username = var.master_username
    password = local.master_secret
    engine   = var.engine
    host     = aws_db_instance.this.address
    port     = local.port
    dbname   = var.db_name
  })
}

###############################################################################
# Subnet group + security group
###############################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${local.identifier}-"
  description = "Subnet group for RDS ${local.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name_prefix = "${local.identifier}-"
  description = "Security group for RDS ${local.identifier}"
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

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "DB ingress from caller-provided SG ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-ingress-sg"
  })
}

# Map form of from_sg. for_each keys come from caller-chosen static labels, so
# SG IDs that are only known after apply (e.g. created in the same run) are
# accepted; the list form above needs every ID known at plan time.
resource "aws_vpc_security_group_ingress_rule" "from_sg_map" {
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
# Parameter group
###############################################################################

resource "aws_db_parameter_group" "this" {
  name_prefix = "${local.identifier}-"
  family      = local.family
  description = "Parameter group for RDS ${local.identifier}"

  dynamic "parameter" {
    for_each = concat(local.default_params, var.extra_parameters)
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-pg"
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

  name_prefix        = "${local.identifier}-mon-"
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

resource "aws_cloudwatch_log_group" "exports" {
  for_each = local.db_log_groups

  name              = "/aws/rds/instance/${each.value.identifier}/${each.value.log_type}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = merge(local.common_tags, {
    Name       = "${each.value.identifier}-${each.value.log_type}-logs"
    LogType    = each.value.log_type
    DBInstance = each.value.identifier
  })
}

###############################################################################
# Primary DB instance
###############################################################################

resource "aws_db_instance" "this" {
  identifier = local.identifier

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.storage_encrypted ? var.kms_key_arn : null

  db_name  = var.db_name
  username = var.master_username
  password = local.master_secret
  port     = local.port

  # null rather than false when unmanaged so existing plans are unchanged.
  manage_master_user_password   = var.manage_master_password ? true : null
  master_user_secret_kms_key_id = local.master_user_secret_kms_key_id

  ca_cert_identifier                  = var.ca_cert_identifier
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period  = var.backup_retention_days
  backup_window            = var.backup_window
  maintenance_window       = var.maintenance_window
  copy_tags_to_snapshot    = var.copy_tags_to_snapshot
  delete_automated_backups = !local.is_prod

  # Deterministic ID prevents the timestamp()-induced perpetual diff.
  # The snapshot is only consulted when the instance is actually destroyed.
  skip_final_snapshot       = !local.is_prod
  final_snapshot_identifier = local.is_prod ? "${local.identifier}-final" : null
  deletion_protection       = var.deletion_protection

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = local.db_log_exports

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = local.apply_immediately

  # Engine upgrades and other supported modifications go through an RDS Blue/Green
  # deployment instead of an in-place modification. Omitted when disabled so
  # existing plans are unchanged.
  dynamic "blue_green_update" {
    for_each = var.blue_green_update ? [1] : []
    content {
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = local.identifier
    Role = "primary"
  })

  depends_on = [
    aws_iam_role_policy_attachment.monitoring,
    aws_cloudwatch_log_group.exports,
  ]
}

###############################################################################
# Read replicas
#
# Each replica is created via the cross-region-capable replicate_source_db
# field. Storage and credential settings are inherited from the primary, so
# only the differentiated knobs are exposed.
###############################################################################

resource "aws_db_instance" "replica" {
  for_each = var.read_replicas

  identifier = "${local.identifier}-replica-${each.key}"

  replicate_source_db = aws_db_instance.this.arn
  instance_class      = coalesce(each.value.instance_class, var.instance_class)

  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.storage_encrypted ? var.kms_key_arn : null

  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az = lookup(each.value, "multi_az", false)

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_days : null
  performance_insights_kms_key_id       = var.performance_insights_enabled ? var.kms_key_arn : null

  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null
  enabled_cloudwatch_logs_exports = local.db_log_exports

  ca_cert_identifier                  = var.ca_cert_identifier
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  skip_final_snapshot = true
  apply_immediately   = local.apply_immediately

  tags = merge(local.common_tags, {
    Name    = "${local.identifier}-replica-${each.key}"
    Role    = "replica"
    Replica = each.key
  })

  depends_on = [
    aws_iam_role_policy_attachment.monitoring,
    aws_cloudwatch_log_group.exports,
  ]
}

###############################################################################
# CloudWatch alarms (optional)
#
# Primary instance only. Storage and memory thresholds are taken in GiB / MiB
# and converted to the bytes the AWS/RDS metrics report.
###############################################################################

locals {
  cloudwatch_alarms = var.create_cloudwatch_alarms ? {
    cpu-utilization = {
      metric_name         = "CPUUtilization"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.cloudwatch_alarm_thresholds.cpu_utilization_percent
      description         = "Average CPU utilization of ${local.identifier} is above ${var.cloudwatch_alarm_thresholds.cpu_utilization_percent}%."
    }
    free-storage-space = {
      metric_name         = "FreeStorageSpace"
      comparison_operator = "LessThanThreshold"
      threshold           = var.cloudwatch_alarm_thresholds.free_storage_space_gb * 1073741824
      description         = "Free storage on ${local.identifier} is below ${var.cloudwatch_alarm_thresholds.free_storage_space_gb} GiB."
    }
    freeable-memory = {
      metric_name         = "FreeableMemory"
      comparison_operator = "LessThanThreshold"
      threshold           = var.cloudwatch_alarm_thresholds.freeable_memory_mb * 1048576
      description         = "Freeable memory on ${local.identifier} is below ${var.cloudwatch_alarm_thresholds.freeable_memory_mb} MiB."
    }
    database-connections = {
      metric_name         = "DatabaseConnections"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.cloudwatch_alarm_thresholds.database_connections
      description         = "Open connections on ${local.identifier} are above ${var.cloudwatch_alarm_thresholds.database_connections}."
    }
  } : {}
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.cloudwatch_alarms

  alarm_name          = "${local.identifier}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric_name
  statistic           = "Average"
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = var.cloudwatch_alarm_thresholds.period_seconds
  evaluation_periods  = var.cloudwatch_alarm_thresholds.evaluation_periods
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-${each.key}"
  })
}
