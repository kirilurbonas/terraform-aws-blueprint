terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
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

  name_prefix   = "${var.name_prefix}-${var.environment}"
  identifier    = "${local.name_prefix}-${var.engine}"
  is_postgres   = var.engine == "postgres"
  port          = var.port != null ? var.port : (local.is_postgres ? 5432 : 3306)
  family        = var.parameter_group_family != null ? var.parameter_group_family : (local.is_postgres ? "postgres${split(".", var.engine_version)[0]}" : "mysql${join(".", slice(split(".", var.engine_version), 0, 2))}")
  is_prod       = var.environment == "prod"
  master_secret = random_password.master.result

  default_params = local.is_postgres ? [
    { name = "log_min_duration_statement", value = "1000" },
    { name = "log_connections", value = "1" },
    { name = "log_disconnections", value = "1" },
    ] : [
    { name = "slow_query_log", value = "1" },
    { name = "long_query_time", value = "1" },
    { name = "log_output", value = "FILE" },
  ]
}

###############################################################################
# Master password (stored in Secrets Manager)
###############################################################################

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "master" {
  name_prefix             = "${local.identifier}-master-"
  description             = "Master credentials for RDS ${local.identifier}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = local.is_prod ? 30 : 0

  tags = merge(local.common_tags, {
    Name = "${local.identifier}-master-secret"
  })
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
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

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period  = var.backup_retention_days
  backup_window            = var.backup_window
  maintenance_window       = var.maintenance_window
  copy_tags_to_snapshot    = true
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

  enabled_cloudwatch_logs_exports = local.is_postgres ? ["postgresql", "upgrade"] : ["audit", "error", "general", "slowquery"]

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = !local.is_prod

  tags = merge(local.common_tags, {
    Name = local.identifier
    Role = "primary"
  })
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

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  skip_final_snapshot = true
  apply_immediately   = !local.is_prod

  tags = merge(local.common_tags, {
    Name    = "${local.identifier}-replica-${each.key}"
    Role    = "replica"
    Replica = each.key
  })
}
