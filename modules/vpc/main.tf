terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

  # Carve /20 public + /20 private subnets out of the VPC CIDR.
  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

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

###############################################################################
# VPC Flow Logs (-> S3)
###############################################################################

resource "aws_s3_bucket" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_s3_bucket_arn == null ? 1 : 0

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

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = length(aws_s3_bucket.flow_logs)

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
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

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  log_destination          = var.flow_logs_s3_bucket_arn != null ? var.flow_logs_s3_bucket_arn : aws_s3_bucket.flow_logs[0].arn
  log_destination_type     = "s3"
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.this.id
  max_aggregation_interval = 60

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}
