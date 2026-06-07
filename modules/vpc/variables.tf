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
    condition = (
      can(cidrnetmask(var.vpc_cidr)) &&
      try(tonumber(split("/", var.vpc_cidr)[1]) >= 16, false) &&
      try(tonumber(split("/", var.vpc_cidr)[1]) <= 24, false)
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR with prefix length /16 - /24 (e.g. 10.0.0.0/16)."
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

variable "flow_logs_file_format" {
  type        = string
  description = "S3 file format for VPC flow logs: plain-text or parquet."
  default     = "plain-text"

  validation {
    condition     = contains(["plain-text", "parquet"], var.flow_logs_file_format)
    error_message = "flow_logs_file_format must be one of: plain-text, parquet."
  }
}

variable "flow_logs_hive_compatible_partitions" {
  type        = bool
  description = "Whether to use hive-compatible S3 key prefixes for VPC flow log delivery."
  default     = false
}

variable "flow_logs_per_hour_partition" {
  type        = bool
  description = "Whether to partition VPC flow log objects by hour instead of day."
  default     = false
}

###############################################################################
# VPC Endpoints
###############################################################################

variable "enable_s3_gateway_endpoint" {
  type        = bool
  description = "Provision a gateway endpoint for S3 (free, attaches to private route tables, saves NAT egress)."
  default     = true
}

variable "interface_endpoints" {
  type        = list(string)
  description = "Service short names (e.g. ecr.api, ecr.dkr, sts, logs, ec2) to expose as interface endpoints in the private subnets. Each one costs per-AZ + per-GB but is cheaper than NAT for chatty workloads."
  default     = []

  validation {
    condition     = length(var.interface_endpoints) == length(distinct(var.interface_endpoints))
    error_message = "interface_endpoints must be unique."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
