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

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto every role."
  default     = {}
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
  description = "Optional inline IAM policy JSON attached to the IRSA role."
  default     = null
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
  description = "Optional aws:SourceIp allow-list applied to the assume-role policy."
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
