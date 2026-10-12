variable "name_prefix" {
  type        = string
  description = "Prefix applied to all named resources."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,24}$", var.name_prefix))
    error_message = "name_prefix must be 1-24 chars, lowercase alphanumerics and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  type        = string
  description = "Project tag applied to every resource."
}

###############################################################################
# Engine
###############################################################################

variable "engine" {
  type        = string
  description = "Aurora engine. Supported: aurora-postgresql, aurora-mysql."

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine must be one of: aurora-postgresql, aurora-mysql."
  }
}

variable "engine_version" {
  type        = string
  description = "Aurora engine version (e.g. \"16.4\" for aurora-postgresql, \"8.0.mysql_aurora.3.08.0\" for aurora-mysql)."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+", var.engine_version))
    error_message = "engine_version must start with <major>.<minor> (e.g. 16.4 or 8.0.mysql_aurora.3.08.0)."
  }
}

variable "instance_class" {
  type        = string
  description = "Default instance class for cluster instances (e.g. db.r6g.large, or db.serverless for Aurora Serverless v2). Overridable per instance."

  validation {
    condition     = can(regex("^db\\.(serverless|[a-z0-9]+\\.[a-z0-9]+)$", var.instance_class))
    error_message = "instance_class must be db.serverless or a valid instance class (e.g. db.r6g.large)."
  }
}

variable "parameter_group_family" {
  type        = string
  description = "Cluster parameter group family (e.g. aurora-postgresql16, aurora-mysql8.0). Derived from engine/version when null."
  default     = null
}

variable "cluster_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  description = "Cluster parameters merged on top of the engine defaults; an entry with the same name as a default replaces it. Static parameters need apply_method = \"pending-reboot\"."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.cluster_parameters : contains(["immediate", "pending-reboot"], p.apply_method)])
    error_message = "cluster_parameters[*].apply_method must be immediate or pending-reboot."
  }

  validation {
    condition     = length(distinct([for p in var.cluster_parameters : p.name])) == length(var.cluster_parameters)
    error_message = "cluster_parameters must not contain the same parameter name twice."
  }
}

###############################################################################
# Storage / encryption
###############################################################################

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key ARN for cluster storage, Performance Insights, and (unless master_user_secret_kms_key_id is set) the master user secret. Null = AWS-managed keys. Storage encryption itself is always on."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account-id>:key/<id>)."
  }
}

variable "storage_type" {
  type        = string
  description = "Cluster storage configuration: aurora (Standard) or aurora-iopt1 (I/O-Optimized). Null leaves the AWS default (Standard)."
  default     = null

  validation {
    condition     = var.storage_type == null || contains(["aurora", "aurora-iopt1"], coalesce(var.storage_type, "aurora"))
    error_message = "storage_type must be aurora or aurora-iopt1."
  }
}

###############################################################################
# Database / credentials
###############################################################################

variable "database_name" {
  type        = string
  description = "Initial database created in the cluster."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only alphanumerics and underscores (max 63 chars)."
  }
}

variable "master_username" {
  type        = string
  description = "Master DB username. The password is always generated and rotated by RDS in a Secrets Manager secret."
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.master_username))
    error_message = "master_username must start with a letter and be at most 16 chars."
  }
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key (ARN, key ID, or alias) for the RDS-managed master user secret. Falls back to kms_key_arn, then to the AWS-managed aws/secretsmanager key."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+|alias/.+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|mrk-[0-9a-f]{32})$", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be a KMS key ARN, alias ARN, alias/<name>, key ID, or multi-Region key ID."
  }
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the cluster."
  default     = true
  nullable    = false
}

variable "enable_http_endpoint" {
  type        = bool
  description = "Enable the RDS Data API (HTTP endpoint) on the cluster."
  default     = false
  nullable    = false
}

###############################################################################
# Networking
###############################################################################

variable "vpc_id" {
  type        = string
  description = "VPC where the cluster security group is created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group. Should be private."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Aurora requires at least 2 subnets across different AZs."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the DB port. Must be literal values known at plan time."
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrnetmask(cidr))
    ])
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDRs."
  }
}

variable "allowed_security_groups" {
  type        = map(string)
  description = "Security groups allowed to reach the DB port, as a map of static caller-chosen label -> SG ID. Labels must be known at plan time; values need not be (e.g. module.eks.node_security_group_id)."
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for label, id in var.allowed_security_groups : can(regex("^[a-zA-Z0-9_-]{1,64}$", label)) && can(regex("^sg-", id))
    ])
    error_message = "allowed_security_groups keys must be 1-64 alphanumerics, hyphens, or underscores, and values must be security group IDs (sg-...)."
  }
}

###############################################################################
# Instances / capacity
###############################################################################

variable "instances" {
  type = map(object({
    instance_class    = optional(string)
    promotion_tier    = optional(number)
    availability_zone = optional(string)
  }))
  description = "Cluster instances keyed by short name (used as the identifier suffix). instance_class defaults to var.instance_class. Aurora picks the writer; promotion_tier (0-15, lower first) sets failover order. Instances are never publicly accessible."
  default = {
    one = {}
    two = {}
  }
  nullable = false

  validation {
    condition     = length(var.instances) >= 1
    error_message = "instances must contain at least one instance."
  }

  validation {
    condition     = alltrue([for k, _ in var.instances : can(regex("^[a-z0-9][a-z0-9-]{0,11}$", k))])
    error_message = "instances keys must be 1-12 chars of lowercase alphanumerics and hyphens, starting with an alphanumeric."
  }

  validation {
    condition = alltrue([
      for _, inst in var.instances : inst.instance_class == null || can(regex("^db\\.(serverless|[a-z0-9]+\\.[a-z0-9]+)$", coalesce(inst.instance_class, "db.serverless")))
    ])
    error_message = "instances[*].instance_class must be db.serverless or a valid instance class (e.g. db.r6g.large)."
  }

  validation {
    condition = alltrue([
      for _, inst in var.instances : inst.promotion_tier == null || (coalesce(inst.promotion_tier, 0) >= 0 && coalesce(inst.promotion_tier, 0) <= 15 && floor(coalesce(inst.promotion_tier, 0)) == coalesce(inst.promotion_tier, 0))
    ])
    error_message = "instances[*].promotion_tier must be a whole number between 0 and 15."
  }
}

variable "serverlessv2_scaling_configuration" {
  type = object({
    min_capacity             = number
    max_capacity             = number
    seconds_until_auto_pause = optional(number)
  })
  description = "Aurora Serverless v2 capacity range in ACUs. Required when any instance uses db.serverless. min_capacity = 0 enables auto-pause (engine-version dependent); seconds_until_auto_pause (300-86400) only applies then."
  default     = null

  validation {
    condition = var.serverlessv2_scaling_configuration == null || (
      try(var.serverlessv2_scaling_configuration.min_capacity >= 0 && var.serverlessv2_scaling_configuration.max_capacity >= 1 && var.serverlessv2_scaling_configuration.max_capacity <= 256, false)
    )
    error_message = "serverlessv2_scaling_configuration capacities must satisfy 0 <= min_capacity and 1 <= max_capacity <= 256."
  }

  validation {
    condition     = var.serverlessv2_scaling_configuration == null || try(var.serverlessv2_scaling_configuration.min_capacity <= var.serverlessv2_scaling_configuration.max_capacity, false)
    error_message = "serverlessv2_scaling_configuration.min_capacity must be less than or equal to max_capacity."
  }

  validation {
    condition = var.serverlessv2_scaling_configuration == null || try(
      var.serverlessv2_scaling_configuration.min_capacity * 2 == floor(var.serverlessv2_scaling_configuration.min_capacity * 2) &&
      var.serverlessv2_scaling_configuration.max_capacity * 2 == floor(var.serverlessv2_scaling_configuration.max_capacity * 2),
      false
    )
    error_message = "serverlessv2_scaling_configuration capacities must be in 0.5 ACU increments."
  }

  validation {
    condition = var.serverlessv2_scaling_configuration == null || try(
      var.serverlessv2_scaling_configuration.seconds_until_auto_pause == null ||
      (var.serverlessv2_scaling_configuration.seconds_until_auto_pause >= 300 && var.serverlessv2_scaling_configuration.seconds_until_auto_pause <= 86400),
      false
    )
    error_message = "serverlessv2_scaling_configuration.seconds_until_auto_pause must be between 300 and 86400."
  }
}

variable "reader_autoscaling" {
  type = object({
    min_capacity       = number
    max_capacity       = number
    target_cpu         = optional(number, 70)
    scale_in_cooldown  = optional(number, 300)
    scale_out_cooldown = optional(number, 300)
  })
  description = "Application Auto Scaling of Aurora Replicas on average reader CPU. min_capacity/max_capacity bound the autoscaled replica count (0-15). Null disables."
  default     = null

  validation {
    condition = var.reader_autoscaling == null || try(
      var.reader_autoscaling.min_capacity >= 0 && var.reader_autoscaling.max_capacity >= 1 && var.reader_autoscaling.max_capacity <= 15 && var.reader_autoscaling.min_capacity <= var.reader_autoscaling.max_capacity,
      false
    )
    error_message = "reader_autoscaling must satisfy 0 <= min_capacity <= max_capacity <= 15 and max_capacity >= 1."
  }

  validation {
    condition     = var.reader_autoscaling == null || try(var.reader_autoscaling.target_cpu > 0 && var.reader_autoscaling.target_cpu <= 100, false)
    error_message = "reader_autoscaling.target_cpu must be greater than 0 and at most 100."
  }

  validation {
    condition     = var.reader_autoscaling == null || try(var.reader_autoscaling.scale_in_cooldown >= 0 && var.reader_autoscaling.scale_out_cooldown >= 0, false)
    error_message = "reader_autoscaling cooldowns must be 0 or greater."
  }
}

###############################################################################
# Availability / backups
###############################################################################

variable "backup_retention_days" {
  type        = number
  description = "Days to keep automated backups."
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "backup_window" {
  type        = string
  description = "Preferred backup window in UTC (e.g. \"03:00-04:00\")."
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "backup_window must be hh24:mi-hh24:mi (e.g. 03:00-04:00)."
  }
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window in UTC (e.g. \"Sun:04:30-Sun:05:30\")."
  default     = "Sun:04:30-Sun:05:30"

  validation {
    condition     = can(regex("^(Mon|Tue|Wed|Thu|Fri|Sat|Sun):([01][0-9]|2[0-3]):[0-5][0-9]-(Mon|Tue|Wed|Thu|Fri|Sat|Sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must be ddd:hh24:mi-ddd:hh24:mi (e.g. Sun:04:30-Sun:05:30)."
  }
}

variable "backtrack_window" {
  type        = number
  description = "Target backtrack window in seconds (aurora-mysql only). 0 disables; maximum 259200 (72 hours)."
  default     = 0
  nullable    = false

  validation {
    condition     = var.backtrack_window >= 0 && var.backtrack_window <= 259200
    error_message = "backtrack_window must be between 0 and 259200 seconds."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Block the cluster from being deleted without first removing this flag."
  default     = true
  nullable    = false
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Allow RDS to apply minor engine upgrades to cluster instances automatically during the maintenance window."
  default     = true
  nullable    = false
}

variable "apply_immediately" {
  type        = bool
  description = "Apply modifications immediately instead of in the next maintenance window. Null keeps the module's environment-based behaviour: immediately outside prod, maintenance window in prod."
  default     = null
}

variable "ca_cert_identifier" {
  type        = string
  description = "Certificate authority for the instances' server certificate (e.g. rds-ca-rsa2048-g1, rds-ca-rsa4096-g1, rds-ca-ecc384-g1). Null leaves the RDS regional default."
  default     = null

  validation {
    condition     = var.ca_cert_identifier == null || can(regex("^rds-ca-[a-z0-9-]+$", var.ca_cert_identifier))
    error_message = "ca_cert_identifier must be an RDS CA identifier of the form rds-ca-<name> (e.g. rds-ca-rsa2048-g1)."
  }
}

###############################################################################
# Observability
###############################################################################

variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights on every cluster instance."
  default     = true
  nullable    = false
}

variable "performance_insights_retention_days" {
  type        = number
  description = "Performance Insights retention in days. 7 is free; longer values (multiples of 31, or 731) are billed. database_insights_mode = \"advanced\" requires at least 465."
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_days)
    error_message = "performance_insights_retention_days must be 7, a multiple of 31 up to 713, or 731."
  }
}

variable "database_insights_mode" {
  type        = string
  description = "CloudWatch Database Insights mode for the cluster: standard or advanced. Advanced requires performance_insights_retention_days >= 465. Null leaves the AWS default (standard)."
  default     = null

  validation {
    condition     = var.database_insights_mode == null || contains(["standard", "advanced"], coalesce(var.database_insights_mode, "standard"))
    error_message = "database_insights_mode must be standard or advanced."
  }
}

variable "monitoring_interval" {
  type        = number
  description = "Enhanced Monitoring interval in seconds for cluster instances. 0 disables. Valid: 0, 1, 5, 10, 15, 30, 60."
  default     = 60
  nullable    = false

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "Log types exported to CloudWatch Logs. Null uses the engine default: [\"postgresql\"] for aurora-postgresql, [\"audit\", \"error\", \"slowquery\"] for aurora-mysql. A module-managed log group is created for each."
  default     = null

  validation {
    condition = var.enabled_cloudwatch_logs_exports == null || alltrue([
      for t in coalesce(var.enabled_cloudwatch_logs_exports, []) : contains(["postgresql", "audit", "error", "general", "slowquery", "iam-db-auth-error"], t)
    ])
    error_message = "enabled_cloudwatch_logs_exports entries must be among: postgresql, audit, error, general, slowquery, iam-db-auth-error."
  }
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "Retention in days for the CloudWatch log groups that receive exported DB logs."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "cloudwatch_log_kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for encrypting the CloudWatch log groups that receive exported DB logs."
  default     = null
}

variable "create_cloudwatch_alarms" {
  type        = bool
  description = "Create cluster-level CloudWatch metric alarms for CPUUtilization, FreeableMemory, DatabaseConnections, and AuroraReplicaLagMaximum."
  default     = false
  nullable    = false
}

variable "cloudwatch_alarm_thresholds" {
  type = object({
    cpu_utilization_percent = optional(number, 80)
    freeable_memory_mb      = optional(number, 256)
    database_connections    = optional(number, 100)
    replica_lag_ms          = optional(number, 1000)
    period_seconds          = optional(number, 300)
    evaluation_periods      = optional(number, 3)
  })
  description = "Thresholds and evaluation window for the alarms created by create_cloudwatch_alarms. Omitted attributes take their defaults. database_connections should be sized to the instance class's max_connections."
  default     = {}
  nullable    = false

  validation {
    condition     = var.cloudwatch_alarm_thresholds.cpu_utilization_percent > 0 && var.cloudwatch_alarm_thresholds.cpu_utilization_percent <= 100
    error_message = "cloudwatch_alarm_thresholds.cpu_utilization_percent must be greater than 0 and at most 100."
  }

  validation {
    condition = (
      var.cloudwatch_alarm_thresholds.freeable_memory_mb > 0 &&
      var.cloudwatch_alarm_thresholds.database_connections > 0 &&
      var.cloudwatch_alarm_thresholds.replica_lag_ms > 0
    )
    error_message = "cloudwatch_alarm_thresholds freeable_memory_mb, database_connections, and replica_lag_ms must be greater than 0."
  }

  validation {
    condition     = var.cloudwatch_alarm_thresholds.period_seconds >= 60 && var.cloudwatch_alarm_thresholds.period_seconds % 60 == 0
    error_message = "cloudwatch_alarm_thresholds.period_seconds must be a positive multiple of 60 (standard-resolution RDS metrics)."
  }

  validation {
    condition     = var.cloudwatch_alarm_thresholds.evaluation_periods >= 1 && floor(var.cloudwatch_alarm_thresholds.evaluation_periods) == var.cloudwatch_alarm_thresholds.evaluation_periods
    error_message = "cloudwatch_alarm_thresholds.evaluation_periods must be a whole number of at least 1."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "SNS topic ARNs notified when an alarm enters the ALARM state."
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.alarm_actions : can(regex("^arn:aws[a-zA-Z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]{1,256}$", arn))
    ])
    error_message = "alarm_actions must contain SNS topic ARNs (arn:<partition>:sns:<region>:<account-id>:<topic>)."
  }
}

variable "ok_actions" {
  type        = list(string)
  description = "SNS topic ARNs notified when an alarm returns to the OK state."
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.ok_actions : can(regex("^arn:aws[a-zA-Z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]{1,256}$", arn))
    ])
    error_message = "ok_actions must contain SNS topic ARNs (arn:<partition>:sns:<region>:<account-id>:<topic>)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
