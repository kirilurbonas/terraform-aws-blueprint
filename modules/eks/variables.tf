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
  description = "Subnet IDs for cluster ENIs and node groups. Use private subnets in production."

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

  validation {
    condition = alltrue([
      for cidr in var.endpoint_public_access_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "endpoint_public_access_cidrs must contain valid IPv4 CIDRs."
  }

  validation {
    condition     = length(var.endpoint_public_access_cidrs) == length(distinct(var.endpoint_public_access_cidrs))
    error_message = "endpoint_public_access_cidrs must contain unique values."
  }
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

variable "oidc_thumbprint_list" {
  type        = list(string)
  description = "Thumbprints for the IAM OIDC provider. Default is the Amazon Root CA 1 thumbprint that backs every public EKS issuer."
  default     = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

###############################################################################
# Access entries (replaces aws-auth)
###############################################################################

variable "authentication_mode" {
  type        = string
  description = "Authentication mode for the cluster. API uses access entries only; API_AND_CONFIG_MAP keeps aws-auth around as well."
  default     = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, API_AND_CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  description = "Whether the IAM principal that runs terraform apply gets a built-in cluster-admin access entry."
  default     = true
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string))
    user_name         = optional(string)
    policy_associations = optional(list(object({
      policy_arn = string
      access_scope = object({
        type       = string
        namespaces = optional(list(string))
      })
    })), [])
  }))
  description = "Access entries to create on the cluster, keyed by a stable name. Each may include policy associations (e.g. AmazonEKSClusterAdminPolicy scoped to cluster, AmazonEKSAdminPolicy scoped to a namespace)."
  default     = {}

  validation {
    condition = alltrue(flatten([
      for _, entry in var.access_entries : [
        for assoc in entry.policy_associations : contains(["cluster", "namespace"], assoc.access_scope.type)
      ]
    ]))
    error_message = "Each access entry policy association access_scope.type must be either cluster or namespace."
  }

  validation {
    condition = alltrue(flatten([
      for _, entry in var.access_entries : [
        for assoc in entry.policy_associations : assoc.access_scope.type != "namespace" || try(length(assoc.access_scope.namespaces), 0) > 0
      ]
    ]))
    error_message = "Namespace-scoped access entry policy associations must include at least one namespace."
  }
}

###############################################################################
# Node groups
###############################################################################

variable "node_groups" {
  type = map(object({
    capacity_type  = optional(string, "ON_DEMAND")
    instance_types = optional(list(string), ["t3.large"])
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    disk_size_gb   = optional(number, 50)
    desired_size   = optional(number, 2)
    min_size       = optional(number, 1)
    max_size       = optional(number, 5)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    enable_ssm_access  = optional(bool, true)
    max_unavailable_pc = optional(number, 33)
  }))
  description = "Map of managed node groups, keyed by short name (e.g. system, apps, gpu). Mix ON_DEMAND/SPOT, instance families, and taints per group."

  validation {
    condition     = length(var.node_groups) > 0
    error_message = "Define at least one node group."
  }

  validation {
    condition = alltrue([
      for k, ng in var.node_groups : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)
    ])
    error_message = "Each node group's capacity_type must be one of: ON_DEMAND, SPOT."
  }

  validation {
    condition = alltrue([
      for k, ng in var.node_groups : length(ng.instance_types) > 0
    ])
    error_message = "Each node group must list at least one instance type."
  }

  validation {
    condition = alltrue([
      for k, ng in var.node_groups : alltrue([
        for t in ng.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)
      ])
    ])
    error_message = "Each taint effect must be one of: NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE."
  }

  validation {
    condition = alltrue([
      for _, ng in var.node_groups :
      ng.min_size >= 0 && ng.desired_size >= 0 && ng.max_size >= 1 && ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size
    ])
    error_message = "Each node group must satisfy min_size <= desired_size <= max_size, with non-negative sizes."
  }

  validation {
    condition = alltrue([
      for _, ng in var.node_groups : ng.disk_size_gb >= 20
    ])
    error_message = "Each node group disk_size_gb must be at least 20 GiB."
  }

  validation {
    condition = alltrue([
      for _, ng in var.node_groups : ng.max_unavailable_pc >= 1 && ng.max_unavailable_pc <= 100
    ])
    error_message = "Each node group max_unavailable_pc must be between 1 and 100."
  }
}

###############################################################################
# Add-ons
###############################################################################

variable "cluster_addons" {
  type = map(object({
    version                     = optional(string)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string)
    configuration_values        = optional(string)
  }))
  description = "Managed EKS add-ons, keyed by add-on name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, ...). Empty = none. Versions default to latest compatible when omitted."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
