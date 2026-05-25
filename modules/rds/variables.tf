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
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to reach the DB port."
  default     = []
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

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
