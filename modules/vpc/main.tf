terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  az_count = length(var.availability_zones)

  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/vpc"
    },
    var.tags,
  )

  name_prefix = "${var.name_prefix}-${var.environment}"

  flow_logs_to_s3                     = var.enable_flow_logs && var.flow_logs_destination_type == "s3"
  flow_logs_to_cloudwatch             = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs"
  use_module_managed_flow_logs_bucket = local.flow_logs_to_s3 && var.flow_logs_s3_bucket_arn == null

  # Default carve: the VPC CIDR is split into 2^subnet_newbits equal blocks.
  # Public takes the first half (index i), private the second half
  # (i + 2^(newbits-1)). With the default newbits = 4 this is exactly the
  # historical /20 layout: public i, private i + 8. The database tier, when
  # enabled, takes the last quarter (i + 2^(newbits-1) + 2^(newbits-2), i.e.
  # i + 12 at the default), which halves how many AZs the carved private tier
  # can hold. Explicit *_subnet_cidrs lists bypass the carve for that tier.
  #
  # cidrsubnet() is wrapped in try() so an over-full carve surfaces as the
  # readable precondition on aws_vpc.this rather than a raw function error.
  private_carve_offset  = pow(2, var.subnet_newbits - 1)
  database_carve_offset = pow(2, var.subnet_newbits - 1) + pow(2, var.subnet_newbits - 2)

  database_tier_carved = var.enable_database_subnets && var.database_subnet_cidrs == null

  # Max AZs each carved tier can hold without overlapping the next tier.
  public_carve_capacity   = pow(2, var.subnet_newbits - 1)
  private_carve_capacity  = local.database_tier_carved ? pow(2, var.subnet_newbits - 2) : pow(2, var.subnet_newbits - 1)
  database_carve_capacity = pow(2, var.subnet_newbits - 2)

  any_tier_carved = (
    var.public_subnet_cidrs == null ||
    var.private_subnet_cidrs == null ||
    local.database_tier_carved
  )

  public_subnet_cidrs = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [
    for i in range(local.az_count) : try(cidrsubnet(var.vpc_cidr, var.subnet_newbits, i), null)
  ]
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [
    for i in range(local.az_count) : try(cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + local.private_carve_offset), null)
  ]
  database_subnet_cidrs = !var.enable_database_subnets ? [] : var.database_subnet_cidrs != null ? var.database_subnet_cidrs : [
    for i in range(local.az_count) : try(cidrsubnet(var.vpc_cidr, var.subnet_newbits, i + local.database_carve_offset), null)
  ]

  database_subnet_count = var.enable_database_subnets ? local.az_count : 0

  nat_gateway_count = var.enable_nat_gateway ? (var.nat_gateway_mode == "per_az" ? local.az_count : 1) : 0
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })

  # Cross-variable input checks. They live here because aws_vpc.this is the
  # one resource that always exists, and variable validation blocks may not
  # reference other variables on the Terraform versions this module supports.
  lifecycle {
    precondition {
      condition     = !local.any_tier_carved || tonumber(split("/", var.vpc_cidr)[1]) + var.subnet_newbits <= 28
      error_message = "vpc_cidr prefix length + subnet_newbits must be <= 28 (AWS's smallest subnet is a /28)."
    }

    precondition {
      condition     = var.public_subnet_cidrs != null || local.az_count <= local.public_carve_capacity
      error_message = "Too many availability_zones for the default public carve at this subnet_newbits (capacity is 2^(subnet_newbits-1)). Lower the AZ count, raise subnet_newbits, or pass public_subnet_cidrs."
    }

    precondition {
      condition     = var.private_subnet_cidrs != null || local.az_count <= local.private_carve_capacity
      error_message = "Too many availability_zones for the default private carve at this subnet_newbits (capacity is 2^(subnet_newbits-1), or 2^(subnet_newbits-2) when the database tier is carved too). Lower the AZ count, raise subnet_newbits, or pass private_subnet_cidrs."
    }

    precondition {
      condition     = !local.database_tier_carved || local.az_count <= local.database_carve_capacity
      error_message = "Too many availability_zones for the default database carve at this subnet_newbits (capacity is 2^(subnet_newbits-2)). Lower the AZ count, raise subnet_newbits, or pass database_subnet_cidrs."
    }

    precondition {
      condition     = var.public_subnet_cidrs == null ? true : length(var.public_subnet_cidrs) == local.az_count
      error_message = "public_subnet_cidrs must have exactly one entry per availability zone."
    }

    precondition {
      condition     = var.private_subnet_cidrs == null ? true : length(var.private_subnet_cidrs) == local.az_count
      error_message = "private_subnet_cidrs must have exactly one entry per availability zone."
    }

    precondition {
      condition     = var.database_subnet_cidrs == null ? true : (var.enable_database_subnets && length(var.database_subnet_cidrs) == local.az_count)
      error_message = "database_subnet_cidrs requires enable_database_subnets = true and must have exactly one entry per availability zone."
    }

    precondition {
      condition     = !var.database_subnets_nat_access || (var.enable_database_subnets && var.enable_nat_gateway)
      error_message = "database_subnets_nat_access requires enable_database_subnets = true and enable_nat_gateway = true."
    }

    precondition {
      condition     = length(setsubtract(keys(var.interface_endpoint_options), var.interface_endpoints)) == 0
      error_message = "Every key in interface_endpoint_options must also be listed in interface_endpoints."
    }

    precondition {
      condition     = !local.flow_logs_to_cloudwatch || var.flow_logs_s3_bucket_arn == null
      error_message = "flow_logs_s3_bucket_arn cannot be set when flow_logs_destination_type = \"cloud-watch-logs\"."
    }

    precondition {
      condition     = var.flow_logs_kms_key_arn == null || !var.enable_flow_logs || local.use_module_managed_flow_logs_bucket
      error_message = "flow_logs_kms_key_arn only applies to the module-managed S3 bucket; it cannot be combined with flow_logs_s3_bucket_arn or the cloud-watch-logs destination. Use flow_logs_cloudwatch_kms_key_arn for CloudWatch Logs."
    }
  }
}

###############################################################################
# Default security group
#
# Declaring aws_default_security_group with no ingress/egress blocks strips
# every rule from the VPC's default SG (AWS ships it allowing all traffic from
# itself), so nothing attached to it by accident can talk. Opt-in until v1.0.
###############################################################################

resource "aws_default_security_group" "this" {
  count = var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-sg"
  })
}

###############################################################################
# Internet Gateway
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name                              = "${local.name_prefix}-private-${var.availability_zones[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_subnet" "database" {
  count = local.database_subnet_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.database_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-${var.availability_zones[count.index]}"
    Tier = "database"
  })
}

resource "aws_db_subnet_group" "database" {
  count = var.enable_database_subnets && var.create_database_subnet_group ? 1 : 0

  name        = "${local.name_prefix}-database"
  description = "Database subnets for ${local.name_prefix}"
  subnet_ids  = aws_subnet.database[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database"
  })
}

###############################################################################
# NAT Gateways
###############################################################################

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Route tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-private-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # In single-NAT mode every private RT points at the only NAT; in per-AZ mode each RT points at the NAT in its own AZ.
  nat_gateway_id = var.nat_gateway_mode == "per_az" ? aws_nat_gateway.this[count.index].id : aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database route tables never get an internet gateway route. A NAT default
# route is added only when database_subnets_nat_access = true.
resource "aws_route_table" "database" {
  count = local.database_subnet_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-database-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "database_nat" {
  count = var.enable_database_subnets && var.database_subnets_nat_access && var.enable_nat_gateway ? local.az_count : 0

  route_table_id         = aws_route_table.database[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_mode == "per_az" ? aws_nat_gateway.this[count.index].id : aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "database" {
  count = local.database_subnet_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}

###############################################################################
# VPC Flow Logs (-> S3 or CloudWatch Logs)
###############################################################################

resource "aws_s3_bucket" "flow_logs" {
  count = local.use_module_managed_flow_logs_bucket ? 1 : 0

  bucket_prefix = "${local.name_prefix}-vpc-flow-logs-"
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    # SSE-S3 by default; SSE-KMS with the caller's key when
    # flow_logs_kms_key_arn is set. The key policy must allow
    # delivery.logs.amazonaws.com to use the key (see README).
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.flow_logs_kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.flow_logs_kms_key_arn
    }

    bucket_key_enabled = var.flow_logs_kms_key_arn != null
  }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "expire-old-flow-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.flow_logs_retention_days
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = local.use_module_managed_flow_logs_bucket ? 1 : 0

  statement {
    sid     = "AllowAWSLogDeliveryAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.flow_logs[0].arn,
    ]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid     = "AllowAWSLogDeliveryWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.flow_logs[0].arn,
      "${aws_s3_bucket.flow_logs[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  count = local.use_module_managed_flow_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name              = "/aws/vpc-flow-logs/${local.name_prefix}"
  retention_in_days = var.flow_logs_cloudwatch_retention_days
  kms_key_id        = var.flow_logs_cloudwatch_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}

data "aws_iam_policy_document" "flow_logs_cloudwatch_assume" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  statement {
    sid     = "AllowVPCFlowLogsAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    # Confused-deputy protection: only flow logs in this account and region.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs_cloudwatch" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  # Scoped to the one module-managed log group and its streams.
  statement {
    sid    = "AllowFlowLogDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow_logs[0].arn,
      "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow_logs_cloudwatch" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name_prefix        = "${local.name_prefix}-vpc-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_cloudwatch_assume[0].json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}

resource "aws_iam_role_policy" "flow_logs_cloudwatch" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name_prefix = "${local.name_prefix}-vpc-flow-logs-"
  role        = aws_iam_role.flow_logs_cloudwatch[0].id
  policy      = data.aws_iam_policy_document.flow_logs_cloudwatch[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  log_destination = (
    local.flow_logs_to_cloudwatch ? aws_cloudwatch_log_group.flow_logs[0].arn :
    var.flow_logs_s3_bucket_arn != null ? var.flow_logs_s3_bucket_arn : aws_s3_bucket.flow_logs[0].arn
  )
  log_destination_type     = var.flow_logs_destination_type
  iam_role_arn             = local.flow_logs_to_cloudwatch ? aws_iam_role.flow_logs_cloudwatch[0].arn : null
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.this.id
  max_aggregation_interval = 60

  # destination_options is S3-only.
  dynamic "destination_options" {
    for_each = local.flow_logs_to_s3 ? [1] : []

    content {
      file_format                = var.flow_logs_file_format
      hive_compatible_partitions = var.flow_logs_hive_compatible_partitions
      per_hour_partition         = var.flow_logs_per_hour_partition
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })

  depends_on = [aws_s3_bucket_policy.flow_logs, aws_iam_role_policy.flow_logs_cloudwatch]
}

###############################################################################
# VPC Endpoints
#
# S3 gateway endpoint is free and saves NAT egress for ECR image pulls and any
# other S3 traffic. Interface endpoints are billed per-AZ + per-GB but cheaper
# than NAT for chatty services (ECR, STS, Logs, EC2).
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  name_prefix = "${local.name_prefix}-vpce-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = length(var.interface_endpoints) > 0 ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from anywhere inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-ingress"
  })
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, aws_route_table.database[*].id)
  policy            = var.s3_gateway_endpoint_policy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = try(var.interface_endpoint_options[each.value].private_dns_enabled, true)
  policy              = try(var.interface_endpoint_options[each.value].policy, null)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-${each.value}"
  })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
