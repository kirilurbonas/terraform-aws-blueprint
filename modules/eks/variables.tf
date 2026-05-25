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

variable "kubernetes_version" {
  type        = string
  description = "EKS control plane Kubernetes version (e.g. \"1.30\")."

  validation {
    condition     = can(regex("^1\\.(2[5-9]|[3-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be 1.25 or later."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID the cluster lives in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for cluster ENIs and node group. Use private subnets in production."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least 2 AZs."
  }
}

variable "endpoint_public_access" {
  type        = bool
  description = "Whether the cluster API server is reachable from the public internet."
  default     = false
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks permitted on the public endpoint. Ignored when endpoint_public_access = false."
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Control plane log streams to ship to CloudWatch."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "enabled_cluster_log_types must be a subset of: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log group retention for cluster logs."
  default     = 90
}

variable "kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for secrets envelope encryption. If null, a key is created."
  default     = null
}

###############################################################################
# Node group
###############################################################################

variable "capacity_type" {
  type        = string
  description = "Node group purchase option: ON_DEMAND or SPOT."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be one of: ON_DEMAND, SPOT."
  }
}

variable "instance_types" {
  type        = list(string)
  description = "EC2 instance types for the node group. Multiple are recommended for SPOT diversification."
  default     = ["t3.large"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types must contain at least one value."
  }
}

variable "ami_type" {
  type        = string
  description = "Node group AMI type (e.g. AL2023_x86_64_STANDARD, BOTTLEROCKET_x86_64)."
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Root EBS volume size for nodes, in GiB."
  default     = 50

  validation {
    condition     = var.node_disk_size_gb >= 20 && var.node_disk_size_gb <= 1000
    error_message = "node_disk_size_gb must be between 20 and 1000."
  }
}

variable "desired_capacity" {
  type        = number
  description = "Initial desired node count. Subsequent changes are ignored so Cluster Autoscaler / Karpenter can manage."
  default     = 2
}

variable "min_capacity" {
  type        = number
  description = "Minimum node count."
  default     = 1
}

variable "max_capacity" {
  type        = number
  description = "Maximum node count."
  default     = 5
}

variable "node_labels" {
  type        = map(string)
  description = "Extra Kubernetes labels applied to every node."
  default     = {}
}

variable "node_taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  description = "Kubernetes taints applied to every node."
  default     = []

  validation {
    condition = alltrue([
      for t in var.node_taints :
      contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)
    ])
    error_message = "Each taint effect must be one of: NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE."
  }
}

variable "enable_ssm_access" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore to nodes for Session Manager access."
  default     = true
}

###############################################################################
# aws-auth
###############################################################################

variable "manage_aws_auth" {
  type        = bool
  description = "Whether the module manages the aws-auth ConfigMap. Requires a configured kubernetes provider."
  default     = false
}

variable "aws_auth_role_map" {
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  description = "Additional IAM roles to map into Kubernetes RBAC. The node role is always mapped automatically."
  default     = []
}

variable "aws_auth_user_map" {
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  description = "IAM users to map into Kubernetes RBAC."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
