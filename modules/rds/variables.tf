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
  description = "Database engine. Supported: postgres, mysql."

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be one of: postgres, mysql."
  }
}

variable "engine_version" {
  type        = string
  description = "RDS engine version (e.g. \"16.3\" for postgres, \"8.0.36\" for mysql)."
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g. db.t3.medium, db.m6i.large)."

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class (e.g. db.m6i.large)."
  }
}

variable "parameter_group_family" {
  type        = string
  description = "Parameter group family (e.g. postgres16, mysql8.0). Derived from engine/version when null."
  default     = null
}

variable "extra_parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Additional DB parameters merged on top of the engine defaults."
  default     = []
}

###############################################################################
# Storage
###############################################################################

variable "allocated_storage_gb" {
  type        = number
  description = "Initial allocated storage in GiB."
  default     = 100

  validation {
    condition     = var.allocated_storage_gb >= 20 && var.allocated_storage_gb <= 65536
    error_message = "allocated_storage_gb must be between 20 and 65536."
  }
}

variable "max_allocated_storage_gb" {
  type        = number
  description = "Upper bound for storage autoscaling. Set equal to allocated_storage_gb to disable."
  default     = 500

  validation {
    condition     = var.max_allocated_storage_gb >= var.allocated_storage_gb
    error_message = "max_allocated_storage_gb must be greater than or equal to allocated_storage_gb."
  }
}

variable "storage_type" {
  type        = string
  description = "Storage type: gp3, io1, or io2."
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be one of: gp3, io1, io2."
  }
}

variable "storage_encrypted" {
  type        = bool
  description = "Whether storage is encrypted at rest."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key for storage / Performance Insights / Secrets Manager. Null = AWS-managed key."
  default     = null
}

###############################################################################
# Database / credentials
###############################################################################

variable "db_name" {
  type        = string
  description = "Initial database name created inside the instance."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a letter and contain only alphanumerics and underscores (max 63 chars)."
  }
}

variable "master_username" {
  type        = string
  description = "Master DB username."
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.master_username))
    error_message = "master_username must start with a letter and be at most 16 chars."
  }
}

variable "port" {
  type        = number
  description = "Listener port. Defaults to engine standard (5432 for postgres, 3306 for mysql)."
  default     = null
}

variable "manage_master_password" {
  type        = bool
  description = "Let RDS generate and rotate the master password in an RDS-managed Secrets Manager secret (manage_master_user_password). When true, no random_password or module-managed secret is created, the password never enters Terraform state, master_password / master_secret_arn return null, and the secret ARN is exposed as master_user_secret_arn."
  default     = false
  nullable    = false
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key (ARN, key ID, or alias) for the RDS-managed master user secret. Only used when manage_master_password = true. Falls back to kms_key_arn, then to the AWS-managed aws/secretsmanager key."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+|alias/.+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|mrk-[0-9a-f]{32})$", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be a KMS key ARN, alias ARN, alias/<name>, key ID, or multi-Region key ID."
  }
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the primary and its read replicas."
  default     = false
  nullable    = false
}

###############################################################################
# Networking
###############################################################################

variable "vpc_id" {
  type        = string
  description = "VPC where the DB security group is created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group. Should be private."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires at least 2 subnets across different AZs."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the DB port."
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrnetmask(cidr))
    ])
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDRs."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to reach the DB port. Every ID must be known at plan time; use allowed_security_groups for IDs created in the same apply."
  default     = []
}

variable "allowed_security_groups" {
  type        = map(string)
  description = "Security groups allowed to reach the DB port, as a map of static caller-chosen label -> SG ID. Required instead of allowed_security_group_ids whenever an ID is computed in the same apply (e.g. module.eks.node_security_group_id). Labels must be known at plan time; values need not be."
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
# Availability / backups
###############################################################################

variable "multi_az" {
  type        = bool
  description = "Deploy a synchronous standby in another AZ."
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Days to keep automated backups."
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "backup_window" {
  type        = string
  description = "Preferred backup window in UTC (e.g. \"03:00-04:00\")."
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window in UTC (e.g. \"Sun:04:30-Sun:05:30\")."
  default     = "Sun:04:30-Sun:05:30"
}

variable "deletion_protection" {
  type        = bool
  description = "Block the instance from being deleted without first removing this flag."
  default     = true
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Allow RDS to apply minor engine upgrades automatically during the maintenance window."
  default     = true
}

variable "apply_immediately" {
  type        = bool
  description = "Apply modifications immediately instead of in the next maintenance window. Null keeps the module's environment-based behaviour: immediately outside prod, maintenance window in prod."
  default     = null
}

variable "copy_tags_to_snapshot" {
  type        = bool
  description = "Copy instance tags to snapshots of the primary instance."
  default     = true
  nullable    = false
}

variable "blue_green_update" {
  type        = bool
  description = "Route changes that would otherwise modify the primary in place (e.g. engine upgrades) through an RDS Blue/Green deployment."
  default     = false
  nullable    = false
}

variable "ca_cert_identifier" {
  type        = string
  description = "Certificate authority for the server certificate (e.g. rds-ca-rsa2048-g1, rds-ca-rsa4096-g1, rds-ca-ecc384-g1). Applied to the primary and replicas. Null leaves the RDS regional default."
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
  description = "Enable Performance Insights."
  default     = true
}

variable "performance_insights_retention_days" {
  type        = number
  description = "Performance Insights retention in days. 7 is free; 31, 93, 186, 372, 731 require long-term retention pricing."
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_days)
    error_message = "performance_insights_retention_days must be 7, a multiple of 31 up to 731, or 731."
  }
}

variable "monitoring_interval" {
  type        = number
  description = "Enhanced Monitoring interval in seconds. 0 disables. Valid: 0, 1, 5, 10, 15, 30, 60."
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
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
  description = "Create CloudWatch metric alarms on the primary instance for CPUUtilization, FreeStorageSpace, FreeableMemory, and DatabaseConnections."
  default     = false
  nullable    = false
}

variable "cloudwatch_alarm_thresholds" {
  type = object({
    cpu_utilization_percent = optional(number, 80)
    free_storage_space_gb   = optional(number, 10)
    freeable_memory_mb      = optional(number, 256)
    database_connections    = optional(number, 100)
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
      var.cloudwatch_alarm_thresholds.free_storage_space_gb > 0 &&
      var.cloudwatch_alarm_thresholds.freeable_memory_mb > 0 &&
      var.cloudwatch_alarm_thresholds.database_connections > 0
    )
    error_message = "cloudwatch_alarm_thresholds free_storage_space_gb, freeable_memory_mb, and database_connections must be greater than 0."
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

###############################################################################
# Read replicas
###############################################################################

variable "read_replicas" {
  type = map(object({
    instance_class = optional(string)
    multi_az       = optional(bool, false)
  }))
  description = "Map of read replicas to create, keyed by short name. Each replica inherits storage, parameter group, and SG from the primary; instance_class defaults to the primary's class when null."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
