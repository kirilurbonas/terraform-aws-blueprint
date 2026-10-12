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

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}

###############################################################################
# Naming
###############################################################################

variable "bucket_name" {
  type        = string
  description = "Exact bucket name. Mutually exclusive with bucket_name_prefix."
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase alphanumerics / dots / hyphens, and start/end with an alphanumeric."
  }

  validation {
    condition     = (var.bucket_name != null) != (var.bucket_name_prefix != null)
    error_message = "Set exactly one of bucket_name or bucket_name_prefix."
  }
}

variable "bucket_name_prefix" {
  type        = string
  description = "Prefix used to generate a unique bucket name when bucket_name is not set."
  default     = null

  validation {
    condition     = var.bucket_name_prefix == null || can(regex("^[a-z0-9.-]{1,37}$", coalesce(var.bucket_name_prefix, "x")))
    error_message = "bucket_name_prefix must be 1-37 chars, lowercase alphanumerics, dots, or hyphens."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Permit terraform destroy to delete a non-empty bucket. Leave false in prod."
  default     = false
}

###############################################################################
# Public access lockdown
###############################################################################

variable "block_public_acls" {
  type        = bool
  description = "Block public ACLs."
  default     = true
}

variable "block_public_policy" {
  type        = bool
  description = "Block public bucket policies."
  default     = true
}

variable "ignore_public_acls" {
  type        = bool
  description = "Ignore public ACLs."
  default     = true
}

variable "restrict_public_buckets" {
  type        = bool
  description = "Restrict public bucket policies."
  default     = true
}

###############################################################################
# Versioning + encryption
###############################################################################

variable "versioning_enabled" {
  type        = bool
  description = "Enable object versioning."
  default     = true
}

variable "sse_algorithm" {
  type        = string
  description = "Server-side encryption algorithm: AES256 or aws:kms."
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be one of: AES256, aws:kms."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN. Required when sse_algorithm = aws:kms."
  default     = null

  validation {
    condition     = var.sse_algorithm != "aws:kms" || var.kms_key_arn != null
    error_message = "kms_key_arn must be set when sse_algorithm = aws:kms."
  }
}

###############################################################################
# Lifecycle
###############################################################################

variable "enable_lifecycle_rules" {
  type        = bool
  description = "Apply the module's lifecycle rule."
  default     = true
}

variable "lifecycle_prefix" {
  type        = string
  description = "Object prefix the lifecycle rule applies to. Empty string = whole bucket."
  default     = ""
}

variable "transition_to_ia_days" {
  type        = number
  description = "Transition current objects to STANDARD_IA after N days. Null = skip."
  default     = 30
}

variable "transition_to_glacier_days" {
  type        = number
  description = "Transition current objects to GLACIER after N days. Null = skip."
  default     = 90
}

variable "expiration_days" {
  type        = number
  description = "Expire current objects after N days. Null = never."
  default     = null
}

variable "noncurrent_version_transition_days" {
  type        = number
  description = "Transition noncurrent versions to GLACIER after N days. Null = skip."
  default     = 30
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Expire noncurrent versions after N days. Null = never."
  default     = 365
}

###############################################################################
# Logging + CORS
###############################################################################

variable "access_logging_target_bucket" {
  type        = string
  description = "Optional bucket name to receive server access logs."
  default     = null
}

variable "access_logging_target_prefix" {
  type        = string
  description = "Key prefix in the target bucket for access log objects."
  default     = null
}

variable "cors_rules" {
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  description = "List of CORS rules. Empty list disables CORS."
  default     = []
}

###############################################################################
# Bucket policy extras
###############################################################################

variable "deny_unencrypted_object_uploads" {
  type        = bool
  description = "Deny PutObject calls that don't request server-side encryption."
  default     = true
}

variable "extra_policy_statements" {
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })), [])
  }))
  description = "Additional bucket-policy statements merged in (e.g. cross-account read access)."
  default     = []
}

###############################################################################
# Object Lock
###############################################################################

variable "object_lock" {
  type = object({
    mode  = string
    days  = optional(number)
    years = optional(number)
  })
  description = "Default Object Lock retention (WORM). Set exactly one of days or years. Requires versioning_enabled = true. Object Lock cannot be disabled once enabled. Null = no Object Lock."
  default     = null

  validation {
    condition     = var.object_lock == null || contains(["GOVERNANCE", "COMPLIANCE"], try(var.object_lock.mode, ""))
    error_message = "object_lock.mode must be one of: GOVERNANCE, COMPLIANCE."
  }

  validation {
    condition     = var.object_lock == null || ((try(var.object_lock.days, null) == null) != (try(var.object_lock.years, null) == null))
    error_message = "object_lock must set exactly one of days or years."
  }

  validation {
    condition = var.object_lock == null || (
      (try(var.object_lock.days, null) == null || try(var.object_lock.days > 0 && floor(var.object_lock.days) == var.object_lock.days, false)) &&
      (try(var.object_lock.years, null) == null || try(var.object_lock.years > 0 && floor(var.object_lock.years) == var.object_lock.years, false))
    )
    error_message = "object_lock.days / object_lock.years must be positive whole numbers."
  }

  validation {
    condition     = var.object_lock == null || var.versioning_enabled
    error_message = "object_lock requires versioning_enabled = true."
  }
}

###############################################################################
# Replication
###############################################################################

variable "replication" {
  type = object({
    destination_bucket_arn    = string
    storage_class             = optional(string)
    destination_kms_key_arn   = optional(string)
    role_arn                  = optional(string)
    delete_marker_replication = optional(bool, false)
  })
  description = <<-EOT
    Replicate every object to another bucket (same- or cross-region, same- or
    cross-account). The destination bucket must already exist with versioning
    enabled. role_arn = null creates a role scoped to this bucket, the
    destination bucket, and the KMS keys involved. When the source bucket uses
    aws:kms, destination_kms_key_arn is required. storage_class = null keeps
    the source object's class. Requires versioning_enabled = true. Null = no
    replication.
  EOT
  default     = null

  validation {
    condition     = var.replication == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", try(var.replication.destination_bucket_arn, "")))
    error_message = "replication.destination_bucket_arn must be an S3 bucket ARN (arn:aws:s3:::bucket-name)."
  }

  validation {
    condition = var.replication == null || try(var.replication.storage_class, null) == null || contains(
      ["STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"],
      try(var.replication.storage_class, ""),
    )
    error_message = "replication.storage_class must be one of: STANDARD, REDUCED_REDUNDANCY, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, DEEP_ARCHIVE, GLACIER_IR."
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
    condition     = var.replication == null || var.versioning_enabled
    error_message = "replication requires versioning_enabled = true."
  }

  validation {
    condition     = var.replication == null || var.sse_algorithm != "aws:kms" || try(var.replication.destination_kms_key_arn, null) != null
    error_message = "replication.destination_kms_key_arn must be set when sse_algorithm = aws:kms (S3 requires a replica key for SSE-KMS objects)."
  }
}

###############################################################################
# Notifications
###############################################################################

variable "enable_eventbridge_notifications" {
  type        = bool
  description = "Send all bucket events to Amazon EventBridge. The module then owns the bucket's notification configuration; do not also manage SNS / SQS / Lambda notifications for this bucket elsewhere."
  default     = false
}

###############################################################################
# Intelligent-Tiering
###############################################################################

variable "intelligent_tiering" {
  type = map(object({
    enabled                  = optional(bool, true)
    prefix                   = optional(string)
    tags                     = optional(map(string))
    archive_access_days      = optional(number)
    deep_archive_access_days = optional(number)
  }))
  description = "Intelligent-Tiering archive configurations, keyed by configuration name. Each enables the Archive Access (90-730 days) and/or Deep Archive Access (180-730 days) tiers for objects in the INTELLIGENT_TIERING storage class, optionally filtered by prefix / tags. Empty map = none."
  default     = {}

  validation {
    condition     = alltrue([for name in keys(var.intelligent_tiering) : can(regex("^[a-zA-Z0-9._-]{1,64}$", name))])
    error_message = "intelligent_tiering keys must be 1-64 chars: alphanumerics, dot, underscore, or hyphen."
  }

  validation {
    condition     = alltrue([for c in values(var.intelligent_tiering) : c.archive_access_days != null || c.deep_archive_access_days != null])
    error_message = "Each intelligent_tiering entry must set archive_access_days, deep_archive_access_days, or both."
  }

  validation {
    condition     = alltrue([for c in values(var.intelligent_tiering) : c.archive_access_days == null || try(c.archive_access_days >= 90 && c.archive_access_days <= 730, false)])
    error_message = "intelligent_tiering archive_access_days must be between 90 and 730."
  }

  validation {
    condition     = alltrue([for c in values(var.intelligent_tiering) : c.deep_archive_access_days == null || try(c.deep_archive_access_days >= 180 && c.deep_archive_access_days <= 730, false)])
    error_message = "intelligent_tiering deep_archive_access_days must be between 180 and 730."
  }

  validation {
    condition     = alltrue([for c in values(var.intelligent_tiering) : c.archive_access_days == null || c.deep_archive_access_days == null || try(c.deep_archive_access_days > c.archive_access_days, false)])
    error_message = "intelligent_tiering deep_archive_access_days must be greater than archive_access_days when both are set."
  }
}
