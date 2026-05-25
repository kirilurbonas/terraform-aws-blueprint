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
  description = "DynamoDB table name for state locks."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.lock_table_name))
    error_message = "lock_table_name must be 3-255 chars, alphanumerics / underscore / dot / hyphen."
  }
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
