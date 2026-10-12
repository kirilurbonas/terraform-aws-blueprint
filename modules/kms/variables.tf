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
  description = "Project tag applied to the key."
}

variable "alias" {
  type        = string
  description = "Alias for the key (without the `alias/` prefix)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]{1,250}$", var.alias))
    error_message = "alias must be 1-250 chars, alphanumerics / underscore / hyphen / slash."
  }
}

variable "description" {
  type        = string
  description = "Free-text description on the KMS key."
  default     = "Customer-managed encryption key"
}

variable "deletion_window_in_days" {
  type        = number
  description = "Pending-deletion window. AWS minimum is 7, max 30."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "multi_region" {
  type        = bool
  description = "Create a multi-region primary key. Set replica_regions to have this module create the replicas."
  default     = false
}

variable "replica_regions" {
  type        = set(string)
  description = "Regions in which to create a replica of the multi-Region primary key, each with the same key policy, deletion window, alias and tags. Requires multi_region = true and must not include the primary key's region."
  default     = []

  validation {
    condition     = alltrue([for r in var.replica_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "replica_regions entries must be AWS region names, e.g. eu-west-1."
  }
}

variable "rotation_period_in_days" {
  type        = number
  description = "Days between automatic key rotations, 90-2560. Null leaves the AWS default (365)."
  default     = null

  validation {
    condition     = var.rotation_period_in_days == null ? true : (var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560 && floor(var.rotation_period_in_days) == var.rotation_period_in_days)
    error_message = "rotation_period_in_days must be a whole number between 90 and 2560."
  }
}

variable "key_administrators" {
  type        = list(string)
  description = "IAM ARNs allowed to administer (rotate / disable / tag) the key. Root is always allowed."
  default     = []
}

variable "key_users" {
  type        = list(string)
  description = "IAM ARNs allowed cryptographic operations (Encrypt / Decrypt / GenerateDataKey)."
  default     = []
}

variable "service_principals" {
  type        = list(string)
  description = "AWS service principals (e.g. s3.amazonaws.com) granted cryptographic operations via the key policy."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto the key."
  default     = {}
}
