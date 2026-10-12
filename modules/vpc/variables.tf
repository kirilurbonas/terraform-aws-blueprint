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

###############################################################################
# Subnet sizing
###############################################################################

variable "subnet_newbits" {
  type        = number
  description = "Bits added to the VPC prefix for each carved subnet (`cidrsubnet` newbits). Public subnets take the first half of the resulting blocks, private the second half, and the database tier (when enabled) the last quarter. The default 4 gives /20s from a /16 and fits 8 AZs, or 4 AZs with the database tier carved. Ignored for any tier whose explicit `*_subnet_cidrs` list is set."
  default     = 4

  validation {
    condition     = var.subnet_newbits >= 2 && var.subnet_newbits <= 12 && floor(var.subnet_newbits) == var.subnet_newbits
    error_message = "subnet_newbits must be a whole number between 2 and 12."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Explicit public subnet CIDRs, one per entry in `availability_zones` (same order). Overrides the `subnet_newbits` carve for this tier. Overlap with other tiers is not checked by the module; AWS rejects it at apply."
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null ? true : alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "public_subnet_cidrs must contain valid IPv4 CIDR blocks (e.g. 10.0.0.0/24)."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Explicit private subnet CIDRs, one per entry in `availability_zones` (same order). Overrides the `subnet_newbits` carve for this tier. Overlap with other tiers is not checked by the module; AWS rejects it at apply."
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null ? true : alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "private_subnet_cidrs must contain valid IPv4 CIDR blocks (e.g. 10.0.16.0/20)."
  }
}

###############################################################################
# Database subnet tier
###############################################################################

variable "enable_database_subnets" {
  type        = bool
  description = "Create a database subnet per AZ with its own route tables that have no internet gateway route, so RDS and similar services stop sharing the application private subnets."
  default     = false
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "Explicit database subnet CIDRs, one per entry in `availability_zones` (same order). Requires `enable_database_subnets = true`. Overrides the `subnet_newbits` carve for this tier."
  default     = null

  validation {
    condition     = var.database_subnet_cidrs == null ? true : alltrue([for c in var.database_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "database_subnet_cidrs must contain valid IPv4 CIDR blocks (e.g. 10.0.192.0/20)."
  }
}

variable "database_subnets_nat_access" {
  type        = bool
  description = "Add a default route via the NAT gateway(s) to the database route tables. Off by default: database subnets have no route to the internet at all. Requires `enable_database_subnets` and `enable_nat_gateway`."
  default     = false
}

variable "create_database_subnet_group" {
  type        = bool
  description = "Create an `aws_db_subnet_group` spanning the database subnets. Only takes effect when `enable_database_subnets = true`."
  default     = true
}

###############################################################################
# Default security group
###############################################################################

variable "manage_default_security_group" {
  type        = bool
  description = "Adopt the VPC's default security group and remove all of its rules (CIS AWS 5.4). Recommended `true`; defaults to `false` for backwards compatibility and will flip at v1.0.0. Enabling it on an existing VPC revokes the default SG's rules, which breaks anything relying on them."
  default     = false
}

###############################################################################
# NAT
###############################################################################

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

variable "flow_logs_destination_type" {
  type        = string
  description = "Flow log destination: `s3` (module-managed or `flow_logs_s3_bucket_arn` bucket) or `cloud-watch-logs` (module-managed log group plus an IAM delivery role)."
  default     = "s3"

  validation {
    condition     = contains(["s3", "cloud-watch-logs"], var.flow_logs_destination_type)
    error_message = "flow_logs_destination_type must be one of: s3, cloud-watch-logs."
  }
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

variable "flow_logs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for SSE-KMS on the module-managed flow-log bucket (S3 Bucket Key enabled). Null keeps SSE-S3 (AES256). The key policy must allow `delivery.logs.amazonaws.com` to use the key; see the README for the statement."
  default     = null

  validation {
    condition     = var.flow_logs_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+$", var.flow_logs_kms_key_arn))
    error_message = "flow_logs_kms_key_arn must be a KMS key or alias ARN (arn:<partition>:kms:<region>:<account>:key/<id>)."
  }
}

variable "flow_logs_cloudwatch_retention_days" {
  type        = number
  description = "Retention for the module-managed CloudWatch Logs flow-log group. Must be a value CloudWatch Logs accepts. Only used when `flow_logs_destination_type = \"cloud-watch-logs\"`."
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_cloudwatch_retention_days)
    error_message = "flow_logs_cloudwatch_retention_days must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "flow_logs_cloudwatch_kms_key_arn" {
  type        = string
  description = "Optional KMS key ARN for the module-managed CloudWatch Logs flow-log group. The key policy must allow the regional `logs.<region>.amazonaws.com` service principal to use it."
  default     = null

  validation {
    condition     = var.flow_logs_cloudwatch_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.flow_logs_cloudwatch_kms_key_arn))
    error_message = "flow_logs_cloudwatch_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>)."
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

variable "s3_gateway_endpoint_policy" {
  type        = string
  description = "Optional JSON endpoint policy for the S3 gateway endpoint. Null leaves the AWS default (full access)."
  default     = null

  validation {
    condition     = var.s3_gateway_endpoint_policy == null ? true : can(jsondecode(var.s3_gateway_endpoint_policy))
    error_message = "s3_gateway_endpoint_policy must be valid JSON."
  }
}

variable "interface_endpoint_options" {
  type = map(object({
    policy              = optional(string)
    private_dns_enabled = optional(bool, true)
  }))
  description = "Per-endpoint settings keyed by a service short name from `interface_endpoints`: an optional JSON endpoint `policy` (null = AWS default full access) and `private_dns_enabled` (default true). Endpoints without an entry keep the defaults."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.interface_endpoint_options : v.policy == null ? true : can(jsondecode(v.policy))])
    error_message = "Every interface_endpoint_options policy must be valid JSON."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto every resource."
  default     = {}
}
