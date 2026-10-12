variable "environment" {
  type        = string
  description = "Environment tag."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  type        = string
  description = "Project tag."
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name (globally unique) that will hold Terraform state."

  validation {
    condition     = can(regex("^[a-z0-9.-]{3,63}$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase alphanumerics / dots / hyphens."
  }
}

variable "lock_table_name" {
  type        = string
  description = "DynamoDB table name for state locks. Required when enable_dynamodb_lock = true; ignored otherwise."
  default     = null

  validation {
    condition     = var.lock_table_name == null || can(regex("^[a-zA-Z0-9_.-]{3,255}$", coalesce(var.lock_table_name, "x")))
    error_message = "lock_table_name must be 3-255 chars, alphanumerics / underscore / dot / hyphen."
  }

  validation {
    condition     = !var.enable_dynamodb_lock || var.lock_table_name != null
    error_message = "lock_table_name must be set when enable_dynamodb_lock = true."
  }
}

variable "enable_dynamodb_lock" {
  type        = bool
  description = "Create the DynamoDB lock table and emit `dynamodb_table` in backend_config_hcl. Set false to use S3-native locking (`use_lockfile = true`, Terraform >= 1.10) with no table; Terraform 1.11 deprecates DynamoDB locking."
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "Optional customer-managed KMS key for state encryption (S3 + DynamoDB). Null = AWS-managed."
  default     = null
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Days to retain old state versions before lifecycle expiration."
  default     = 365
}

variable "tags" {
  type        = map(string)
  description = "Additional tags."
  default     = {}
}

variable "access_logging" {
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  description = "Server access logging for the state bucket. target_prefix = null uses \"<bucket_name>/\". Null = no access logging."
  default     = null

  validation {
    condition     = var.access_logging == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", try(var.access_logging.target_bucket, "")))
    error_message = "access_logging.target_bucket must be a bucket name (3-63 chars, lowercase alphanumerics / dots / hyphens)."
  }

  validation {
    condition     = var.access_logging == null || try(var.access_logging.target_bucket, null) != var.bucket_name
    error_message = "access_logging.target_bucket must not be the state bucket itself."
  }
}

variable "replication" {
  type = object({
    destination_bucket_arn  = string
    destination_kms_key_arn = optional(string)
    role_arn                = optional(string)
  })
  description = <<-EOT
    Replicate state objects to a DR bucket (typically in another region). The
    destination bucket must already exist with versioning enabled. role_arn =
    null creates a role scoped to the two buckets and the KMS keys involved.
    destination_kms_key_arn is required when kms_key_arn is set. Delete markers
    are not replicated. Null = no replication.
  EOT
  default     = null

  validation {
    condition     = var.replication == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", try(var.replication.destination_bucket_arn, "")))
    error_message = "replication.destination_bucket_arn must be an S3 bucket ARN (arn:aws:s3:::bucket-name)."
  }

  validation {
    condition     = var.replication == null || try(var.replication.destination_kms_key_arn, null) == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", try(var.replication.destination_kms_key_arn, "")))
    error_message = "replication.destination_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }

  validation {
    condition     = var.replication == null || try(var.replication.role_arn, null) == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", try(var.replication.role_arn, "")))
    error_message = "replication.role_arn must be an IAM role ARN."
  }

  validation {
    condition     = var.replication == null || var.kms_key_arn == null || try(var.replication.destination_kms_key_arn, null) != null
    error_message = "replication.destination_kms_key_arn must be set when kms_key_arn is set (S3 requires a replica key for SSE-KMS objects)."
  }
}
