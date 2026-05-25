variable "name_prefix" {
  type        = string
  description = "Prefix applied to all named resources (e.g. `platform`)."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.name_prefix))
    error_message = "name_prefix must be 1-32 chars, lowercase alphanumerics and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, staging, prod). Drives tagging and lifecycle behavior."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  type        = string
  description = "Project name tag applied to every resource for cost allocation."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC. Must be a valid IPv4 CIDR with prefix length /16 - /24."

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr prefix length must be between /16 and /24."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AZs to deploy subnets into. At least 2 required for production HA."

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required."
  }

  validation {
    condition     = length(var.availability_zones) == length(distinct(var.availability_zones))
    error_message = "availability_zones must contain unique values."
  }
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Whether to provision NAT gateways for private subnet egress."
  default     = true
}

variable "nat_gateway_mode" {
  type        = string
  description = "NAT gateway topology: `single` (one shared NAT, cost-optimized) or `per_az` (NAT in every AZ, HA)."
  default     = "per_az"

  validation {
    condition     = contains(["single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be one of: single, per_az."
  }
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs. Logs go to the bucket at `flow_logs_s3_bucket_arn` if set, otherwise to a module-managed bucket."
  default     = true
}

variable "flow_logs_s3_bucket_arn" {
  type        = string
  description = "Optional pre-existing S3 bucket ARN for flow logs. If null, the module creates a dedicated bucket."
  default     = null
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Number of days to retain VPC flow logs in S3 before expiration."
  default     = 365

  validation {
    condition     = var.flow_logs_retention_days >= 1 && var.flow_logs_retention_days <= 3650
    error_message = "flow_logs_retention_days must be between 1 and 3650."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
