variable "name_prefix" {
  type        = string
  description = "Prefix applied to every role name."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,32}$", var.name_prefix))
    error_message = "name_prefix must be 1-32 chars (alphanumerics, hyphen, underscore)."
  }
}

variable "project" {
  type        = string
  description = "Project tag applied to all roles."
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod), applied as the Environment tag. Optional because IAM roles are often account-wide rather than per-environment; set it whenever the roles belong to one environment so they satisfy the library's tagging contract."
  default     = null

  validation {
    condition     = var.environment == null || contains(["dev", "staging", "prod"], coalesce(var.environment, "dev"))
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto every role."
  default     = {}
}

variable "permissions_boundary_arn" {
  type        = string
  description = "ARN of an IAM managed policy set as the permissions boundary on every role this module creates. Null means no boundary."
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account-id|aws>:policy/<path/name>)."
  }
}

###############################################################################
# eks_cluster_role
###############################################################################

variable "create_eks_cluster_role" {
  type        = bool
  description = "Whether to create the EKS control-plane service role."
  default     = false
}

###############################################################################
# eks_node_role
###############################################################################

variable "create_eks_node_role" {
  type        = bool
  description = "Whether to create the EKS node-group instance role."
  default     = false
}

###############################################################################
# irsa_role
###############################################################################

variable "create_irsa_role" {
  type        = bool
  description = "Whether to create an IRSA role."
  default     = false
}

variable "irsa_oidc_provider_arn" {
  type        = string
  description = "ARN of the IAM OIDC provider that backs IRSA for the target EKS cluster."
  default     = null
}

variable "irsa_oidc_provider_url" {
  type        = string
  description = "OIDC issuer URL for the target EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE)."
  default     = null
}

variable "irsa_namespace" {
  type        = string
  description = "Kubernetes namespace of the service account that may assume this role."
  default     = "default"
}

variable "irsa_service_account_name" {
  type        = string
  description = "Kubernetes service account name that may assume this role."
  default     = null
}

variable "irsa_managed_policy_arns" {
  type        = list(string)
  description = "AWS-managed policies to attach to the IRSA role."
  default     = []
}

variable "irsa_inline_policy_json" {
  type        = string
  description = "Optional inline IAM policy JSON attached to the IRSA role. If the JSON is only known after apply (computed in the same run), also set create_irsa_inline_policy = true."
  default     = null
}

variable "create_irsa_inline_policy" {
  type        = bool
  description = "Attach irsa_inline_policy_json even when its value is unknown at plan time. Required when the policy JSON is computed in the same apply; without it Terraform cannot determine whether to create the policy."
  default     = false
  nullable    = false
}

###############################################################################
# ci_deployer_role
###############################################################################

variable "create_ci_deployer_role" {
  type        = bool
  description = "Whether to create a cross-account CI/CD deployer role."
  default     = false
}

variable "ci_trusted_principal_arns" {
  type        = list(string)
  description = "ARNs of IAM principals (typically a CI-account role or GitHub OIDC role) allowed to assume the deployer role."
  default     = []
}

variable "ci_external_id" {
  type        = string
  description = "Optional sts:ExternalId required when assuming the deployer role."
  default     = null
  sensitive   = true
}

variable "ci_source_ip_cidrs" {
  type        = list(string)
  description = "Optional aws:SourceIp allow-list applied to every trust statement of the deployer role (cross-account and GitHub OIDC)."
  default     = []
}

variable "ci_max_session_duration" {
  type        = number
  description = "Maximum session duration (seconds) for the deployer role. Range 3600 - 43200."
  default     = 3600

  validation {
    condition     = var.ci_max_session_duration >= 3600 && var.ci_max_session_duration <= 43200
    error_message = "ci_max_session_duration must be between 3600 and 43200."
  }
}

variable "ci_allowed_statements" {
  type = list(object({
    sid       = optional(string)
    actions   = list(string)
    resources = list(string)
  }))
  description = "Allow-only IAM statements granted to the deployer role. Keep tightly scoped."
  default     = []
}

variable "github_oidc" {
  type = object({
    repositories  = list(string)
    branches      = optional(list(string), [])
    environments  = optional(list(string), [])
    tags          = optional(list(string), [])
    pull_requests = optional(bool, false)
    provider_arn  = optional(string)
  })
  description = <<-EOT
    GitHub Actions OIDC trust for the CI deployer role. Null disables it.
    `repositories` are "owner/repo" (the repo part may use `*` wildcards; the
    owner may not). Each repository is trusted only for the listed `branches`,
    `tags`, `environments`, and/or pull_request events — at least one selector
    is required. Set `provider_arn` to an existing
    token.actions.githubusercontent.com OIDC provider, or set
    create_github_oidc_provider = true instead.
  EOT
  default     = null

  validation {
    condition     = var.github_oidc == null ? true : length(var.github_oidc.repositories) > 0
    error_message = "github_oidc.repositories must list at least one \"owner/repo\"."
  }

  # A wildcard or empty owner would let any GitHub account assume the role.
  validation {
    condition = var.github_oidc == null ? true : alltrue([
      for r in var.github_oidc.repositories : can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._*-]+$", r))
    ])
    error_message = "github_oidc.repositories entries must be \"owner/repo\" with a literal owner (no wildcards); only the repo part may contain `*`."
  }

  validation {
    condition = var.github_oidc == null ? true : (
      length(var.github_oidc.branches) + length(var.github_oidc.tags) + length(var.github_oidc.environments) > 0 || var.github_oidc.pull_requests
    )
    error_message = "github_oidc needs at least one of branches, tags, environments, or pull_requests = true; trusting every ref of a repository must be explicit (e.g. branches = [\"*\"])."
  }

  validation {
    condition = var.github_oidc == null ? true : alltrue([
      for v in concat(var.github_oidc.branches, var.github_oidc.tags, var.github_oidc.environments) : can(regex("^[^:]+$", v))
    ])
    error_message = "github_oidc branches, tags, and environments must be non-empty and must not contain ':'."
  }

  validation {
    condition = var.github_oidc == null ? true : (
      var.github_oidc.provider_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc.provider_arn))
    )
    error_message = "github_oidc.provider_arn must be the ARN of a token.actions.githubusercontent.com IAM OIDC provider."
  }
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Create the account's IAM OIDC provider for https://token.actions.githubusercontent.com. Only one can exist per account; leave false and pass github_oidc.provider_arn if it already exists. Requires create_ci_deployer_role and github_oidc."
  default     = false
}
