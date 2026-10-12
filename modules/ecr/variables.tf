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
  description = "Additional tags merged onto every repository."
  default     = {}
}

###############################################################################
# Repositories
###############################################################################

variable "repositories" {
  type = map(object({
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, false)
    keep_tagged_count    = optional(number)
    tagged_prefixes      = optional(list(string))
    untagged_expire_days = optional(number)
    keep_any_count       = optional(number)
    pull_principals      = optional(list(string), [])
    push_principals      = optional(list(string), [])
    lambda_pull          = optional(bool, false)
  }))
  description = <<-EOT
    ECR repositories, keyed by repository name. Lifecycle fields left null use
    the module-level lifecycle_* defaults. pull_principals / push_principals
    are 12-digit AWS account IDs or IAM ARNs (root, role or user) granted
    cross-account pull / push through a repository policy; lambda_pull = true
    lets Lambda functions in this account and in the pull_principals' accounts
    pull images. A repository policy is created only when one of those three is
    set.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for name in keys(var.repositories) :
      length(name) >= 2 && length(name) <= 256 && can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", name))
    ])
    error_message = "repositories keys must be valid ECR repository names: 2-256 chars, lowercase alphanumerics separated by '.', '_', '-' or '/'."
  }

  validation {
    condition     = alltrue([for r in values(var.repositories) : contains(["IMMUTABLE", "MUTABLE"], r.image_tag_mutability)])
    error_message = "repositories image_tag_mutability must be one of: IMMUTABLE, MUTABLE."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      r.untagged_expire_days == null || try(r.untagged_expire_days >= 1 && floor(r.untagged_expire_days) == r.untagged_expire_days, false)
    ])
    error_message = "repositories untagged_expire_days must be a whole number >= 1."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      r.keep_tagged_count == null || try(r.keep_tagged_count >= 1 && floor(r.keep_tagged_count) == r.keep_tagged_count, false)
    ])
    error_message = "repositories keep_tagged_count must be a whole number >= 1."
  }

  validation {
    condition = alltrue([
      for r in values(var.repositories) :
      r.keep_any_count == null || try(r.keep_any_count >= 1 && floor(r.keep_any_count) == r.keep_any_count, false)
    ])
    error_message = "repositories keep_any_count must be a whole number >= 1."
  }

  validation {
    condition = alltrue(flatten([
      for r in values(var.repositories) : [for p in coalesce(r.tagged_prefixes, []) : length(p) > 0]
    ]))
    error_message = "repositories tagged_prefixes entries must be non-empty strings."
  }

  validation {
    condition = alltrue(flatten([
      for r in values(var.repositories) : [for p in concat(r.pull_principals, r.push_principals) : !strcontains(p, "*")]
    ]))
    error_message = "repositories pull_principals / push_principals must not contain '*'; name each account or IAM principal explicitly."
  }

  validation {
    condition = alltrue(flatten([
      for r in values(var.repositories) : [
        for p in concat(r.pull_principals, r.push_principals) :
        can(regex("^([0-9]{12}|arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+))$", p))
      ]
    ]))
    error_message = "repositories pull_principals / push_principals entries must be 12-digit account IDs or IAM root / role / user ARNs."
  }
}

###############################################################################
# Encryption
###############################################################################

variable "encryption_type" {
  type        = string
  description = "Repository encryption: KMS or AES256. Applies to every repository and cannot be changed without replacing the repository."
  default     = "KMS"

  validation {
    condition     = contains(["KMS", "AES256"], var.encryption_type)
    error_message = "encryption_type must be one of: KMS, AES256."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN used when encryption_type = KMS. Null uses the AWS managed key (aws/ecr)."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", coalesce(var.kms_key_arn, "x")))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }

  validation {
    condition     = var.kms_key_arn == null || var.encryption_type == "KMS"
    error_message = "kms_key_arn can only be set when encryption_type = KMS."
  }
}

###############################################################################
# Lifecycle policy defaults
###############################################################################

variable "lifecycle_untagged_expire_days" {
  type        = number
  description = "Default: expire untagged images this many days after push."
  default     = 14

  validation {
    condition     = var.lifecycle_untagged_expire_days >= 1 && floor(var.lifecycle_untagged_expire_days) == var.lifecycle_untagged_expire_days
    error_message = "lifecycle_untagged_expire_days must be a whole number >= 1."
  }
}

variable "lifecycle_keep_tagged_count" {
  type        = number
  description = "Default: number of images to keep whose tag starts with one of lifecycle_tagged_prefixes."
  default     = 30

  validation {
    condition     = var.lifecycle_keep_tagged_count >= 1 && floor(var.lifecycle_keep_tagged_count) == var.lifecycle_keep_tagged_count
    error_message = "lifecycle_keep_tagged_count must be a whole number >= 1."
  }
}

variable "lifecycle_tagged_prefixes" {
  type        = list(string)
  description = "Default: tag prefixes counted by the keep-tagged rule. Empty list omits that rule."
  default     = ["v", "release"]

  validation {
    condition     = alltrue([for p in var.lifecycle_tagged_prefixes : length(p) > 0])
    error_message = "lifecycle_tagged_prefixes entries must be non-empty strings."
  }
}

variable "lifecycle_keep_any_count" {
  type        = number
  description = "Default: number of images to keep among those not matched by the untagged or keep-tagged rules (e.g. commit-SHA tags). Evaluated last. Null omits that rule."
  default     = 100

  validation {
    condition     = var.lifecycle_keep_any_count == null || try(var.lifecycle_keep_any_count >= 1 && floor(var.lifecycle_keep_any_count) == var.lifecycle_keep_any_count, false)
    error_message = "lifecycle_keep_any_count must be a whole number >= 1, or null."
  }
}

###############################################################################
# Registry-level settings (account singletons)
###############################################################################

variable "registry_scanning" {
  type = object({
    scan_type = string
    rules = optional(list(object({
      scan_frequency = string
      filter         = optional(string, "*")
    })), [])
  })
  description = "Registry scanning configuration (BASIC or ENHANCED). Registry-wide singleton: overrides repository scan_on_push settings and any configuration made elsewhere. Manage it from one stack per account and Region. Null = leave untouched."
  default     = null

  validation {
    condition     = var.registry_scanning == null || contains(["BASIC", "ENHANCED"], try(var.registry_scanning.scan_type, ""))
    error_message = "registry_scanning.scan_type must be one of: BASIC, ENHANCED."
  }

  validation {
    condition = var.registry_scanning == null || alltrue([
      for r in try(var.registry_scanning.rules, []) : contains(["SCAN_ON_PUSH", "CONTINUOUS_SCAN", "MANUAL"], r.scan_frequency)
    ])
    error_message = "registry_scanning.rules scan_frequency must be one of: SCAN_ON_PUSH, CONTINUOUS_SCAN, MANUAL."
  }

  validation {
    condition = var.registry_scanning == null || try(var.registry_scanning.scan_type, "") == "ENHANCED" || alltrue([
      for r in try(var.registry_scanning.rules, []) : r.scan_frequency != "CONTINUOUS_SCAN"
    ])
    error_message = "registry_scanning CONTINUOUS_SCAN requires scan_type = ENHANCED."
  }

  validation {
    condition     = var.registry_scanning == null || alltrue([for r in try(var.registry_scanning.rules, []) : length(r.filter) > 0])
    error_message = "registry_scanning.rules filter must be a non-empty wildcard pattern."
  }
}

variable "pull_through_cache_rules" {
  type = map(object({
    upstream_registry_url = string
    credential_arn        = optional(string)
  }))
  description = "Pull-through cache rules, keyed by the ECR repository prefix (e.g. ecr-public, docker-hub). credential_arn is a Secrets Manager secret whose name starts with ecr-pullthroughcache/, required by authenticated upstreams. Registry-level: manage from one stack per account and Region."
  default     = {}

  validation {
    condition = alltrue([
      for prefix in keys(var.pull_through_cache_rules) :
      length(prefix) >= 2 && length(prefix) <= 30 && can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", prefix))
    ])
    error_message = "pull_through_cache_rules keys must be 2-30 chars, lowercase alphanumerics separated by '.', '_', '-' or '/'."
  }

  validation {
    condition     = alltrue([for r in values(var.pull_through_cache_rules) : length(r.upstream_registry_url) > 0])
    error_message = "pull_through_cache_rules upstream_registry_url must be set."
  }

  validation {
    condition = alltrue([
      for r in values(var.pull_through_cache_rules) :
      r.credential_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:ecr-pullthroughcache/.+$", r.credential_arn))
    ])
    error_message = "pull_through_cache_rules credential_arn must be a Secrets Manager secret ARN whose name starts with ecr-pullthroughcache/."
  }
}

variable "replication_regions" {
  type        = list(string)
  description = "Regions to replicate every repository in this registry to, within the same account. Registry-wide singleton: replaces any existing replication configuration. Must not include the current Region. Empty list = leave untouched."
  default     = []

  validation {
    condition     = alltrue([for r in var.replication_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "replication_regions entries must be AWS region names, e.g. eu-west-1."
  }

  validation {
    condition     = length(var.replication_regions) == length(distinct(var.replication_regions)) && length(var.replication_regions) <= 25
    error_message = "replication_regions must be unique and contain at most 25 Regions."
  }
}
