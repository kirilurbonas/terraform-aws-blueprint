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
