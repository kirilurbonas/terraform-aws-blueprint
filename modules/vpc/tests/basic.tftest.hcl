# Plan-only tests that exercise variable wiring without contacting AWS.
# CI runs these in `terraform test -refresh=false` mode against a fake
# provider — no resources are actually created.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
}

variables {
  name_prefix        = "test"
  environment        = "dev"
  project            = "blueprint-tests"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
  nat_gateway_mode   = "single"
  enable_flow_logs   = false
}

run "defaults_plan_cleanly" {
  command = plan
}

run "module_managed_flow_logs_bucket_is_hardened" {
  command = plan

  variables {
    enable_flow_logs                     = true
    flow_logs_file_format                = "parquet"
    flow_logs_hive_compatible_partitions = true
    flow_logs_per_hour_partition         = true
  }

  assert {
    condition     = length(aws_s3_bucket_policy.flow_logs) == 1
    error_message = "module-managed flow log buckets should include a delivery policy"
  }

  assert {
    condition     = length(aws_s3_bucket_ownership_controls.flow_logs) == 1
    error_message = "module-managed flow log buckets should disable ACLs"
  }

  assert {
    condition     = aws_flow_log.this[0].destination_options[0].file_format == "parquet"
    error_message = "flow log destination options should honor the requested file format"
  }
}

run "per_az_nat_creates_per_az_routes" {
  command = plan

  variables {
    nat_gateway_mode = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == length(var.availability_zones)
    error_message = "per_az mode should create one NAT gateway per AZ"
  }
}

run "rejects_too_few_azs" {
  command         = plan
  expect_failures = [var.availability_zones]

  variables {
    availability_zones = ["us-east-1a"]
  }
}

run "rejects_bad_nat_mode" {
  command         = plan
  expect_failures = [var.nat_gateway_mode]

  variables {
    nat_gateway_mode = "double"
  }
}

run "rejects_bad_cidr" {
  command         = plan
  expect_failures = [var.vpc_cidr]

  variables {
    vpc_cidr = "not-a-cidr"
  }
}

###############################################################################
# Subnet carve
###############################################################################

run "default_carve_is_unchanged" {
  command = plan

  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
    error_message = "default public carve must stay cidrsubnet(vpc_cidr, 4, i)"
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
    error_message = "default private carve must stay cidrsubnet(vpc_cidr, 4, i + 8)"
  }

  assert {
    condition     = length(aws_subnet.database) == 0 && length(aws_route_table.database) == 0 && length(aws_db_subnet_group.database) == 0
    error_message = "the database tier must be off by default"
  }

  assert {
    condition     = length(aws_default_security_group.this) == 0
    error_message = "the default security group must not be managed by default"
  }
}

run "subnet_newbits_resizes_the_carve" {
  command = plan

  variables {
    subnet_newbits = 8
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.0.0.0/24", "10.0.1.0/24"]
    error_message = "subnet_newbits = 8 should carve /24 public subnets from the bottom of the VPC"
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.128.0/24", "10.0.129.0/24"]
    error_message = "subnet_newbits = 8 should start the private tier halfway through the VPC"
  }
}

run "explicit_subnet_cidrs_take_precedence" {
  command = plan

  variables {
    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.64.0/18", "10.0.128.0/18"]
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.0.0.0/24", "10.0.1.0/24"]
    error_message = "public_subnet_cidrs should override the carve"
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.64.0/18", "10.0.128.0/18"]
    error_message = "private_subnet_cidrs should override the carve"
  }
}

run "rejects_subnet_newbits_out_of_range" {
  command         = plan
  expect_failures = [var.subnet_newbits]

  variables {
    subnet_newbits = 1
  }
}

run "rejects_subnet_newbits_too_small_for_vpc" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    vpc_cidr       = "10.0.0.0/24"
    subnet_newbits = 6
  }
}

run "rejects_invalid_public_subnet_cidr" {
  command         = plan
  expect_failures = [var.public_subnet_cidrs]

  variables {
    public_subnet_cidrs = ["10.0.0.0/24", "not-a-cidr"]
  }
}

run "rejects_invalid_private_subnet_cidr" {
  command         = plan
  expect_failures = [var.private_subnet_cidrs]

  variables {
    private_subnet_cidrs = ["10.0.128.0/24", "10.0.300.0/24"]
  }
}

run "rejects_subnet_cidr_count_mismatch" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    public_subnet_cidrs = ["10.0.0.0/24"]
  }
}

run "rejects_too_many_azs_for_carve" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    subnet_newbits     = 2
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

###############################################################################
# Database tier
###############################################################################

run "database_tier_is_isolated" {
  command = plan

  # Route table IDs are unknown at plan; pin them so the endpoint wiring can be asserted.
  override_resource {
    target          = aws_route_table.private
    override_during = plan
    values = {
      id = "rtb-private"
    }
  }

  override_resource {
    target          = aws_route_table.database
    override_during = plan
    values = {
      id = "rtb-database"
    }
  }

  variables {
    availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c"]
    enable_database_subnets = true
  }

  assert {
    condition     = aws_subnet.database[*].cidr_block == ["10.0.192.0/20", "10.0.208.0/20", "10.0.224.0/20"]
    error_message = "default database carve should be cidrsubnet(vpc_cidr, 4, i + 12)"
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
    error_message = "enabling the database tier must not move the private subnets"
  }

  assert {
    condition     = length(aws_route_table.database) == 3 && length(aws_route_table_association.database) == 3
    error_message = "each database subnet should get its own route table"
  }

  assert {
    condition     = length(aws_route.database_nat) == 0
    error_message = "database route tables must have no default route unless database_subnets_nat_access = true"
  }

  assert {
    condition     = aws_db_subnet_group.database[0].name == "test-dev-database"
    error_message = "a DB subnet group should be created by default with the tier"
  }

  assert {
    condition     = output.database_subnet_group_name == "test-dev-database"
    error_message = "database_subnet_group_name should expose the subnet group"
  }

  assert {
    condition     = contains(aws_vpc_endpoint.s3_gateway[0].route_table_ids, "rtb-database") && contains(aws_vpc_endpoint.s3_gateway[0].route_table_ids, "rtb-private")
    error_message = "the S3 gateway endpoint should attach to private and database route tables"
  }
}

run "database_tier_fits_four_azs" {
  command = plan

  variables {
    availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    enable_database_subnets = true
  }

  assert {
    condition     = aws_subnet.database[3].cidr_block == "10.0.240.0/20"
    error_message = "the fourth database subnet should use the last /20 of the VPC"
  }
}

run "database_nat_access_adds_nat_routes" {
  command = plan

  variables {
    enable_database_subnets      = true
    database_subnets_nat_access  = true
    create_database_subnet_group = false
  }

  assert {
    condition     = length(aws_route.database_nat) == 2
    error_message = "database_subnets_nat_access should add a NAT route per database route table"
  }

  assert {
    condition     = length(aws_db_subnet_group.database) == 0 && output.database_subnet_group_name == null
    error_message = "create_database_subnet_group = false should skip the subnet group"
  }
}

run "explicit_database_subnet_cidrs" {
  command = plan

  variables {
    enable_database_subnets = true
    database_subnet_cidrs   = ["10.0.100.0/24", "10.0.101.0/24"]
  }

  assert {
    condition     = aws_subnet.database[*].cidr_block == ["10.0.100.0/24", "10.0.101.0/24"]
    error_message = "database_subnet_cidrs should override the carve"
  }
}

run "rejects_too_many_azs_for_database_carve" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    availability_zones      = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e"]
    enable_database_subnets = true
  }
}

run "rejects_database_cidrs_without_tier" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    database_subnet_cidrs = ["10.0.100.0/24", "10.0.101.0/24"]
  }
}

run "rejects_invalid_database_subnet_cidr" {
  command         = plan
  expect_failures = [var.database_subnet_cidrs]

  variables {
    enable_database_subnets = true
    database_subnet_cidrs   = ["10.0.100.0/24", "bogus"]
  }
}

run "rejects_database_nat_access_without_nat" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    enable_nat_gateway          = false
    enable_database_subnets     = true
    database_subnets_nat_access = true
  }
}

###############################################################################
# Default security group
###############################################################################

run "manage_default_security_group_strips_rules" {
  command = plan

  variables {
    manage_default_security_group = true
  }

  assert {
    condition     = length(aws_default_security_group.this) == 1
    error_message = "manage_default_security_group should adopt the default SG"
  }
}

###############################################################################
# Flow logs: KMS and CloudWatch Logs
###############################################################################

run "flow_logs_bucket_defaults_to_sse_s3" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "the module-managed bucket should keep SSE-S3 by default"
  }
}

run "flow_logs_bucket_uses_cmk_when_given" {
  command = plan

  variables {
    enable_flow_logs      = true
    flow_logs_kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "flow_logs_kms_key_arn should switch the bucket to SSE-KMS"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.flow_logs_kms_key_arn
    error_message = "SSE-KMS should use the supplied key"
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys should be enabled with SSE-KMS"
  }
}

run "rejects_invalid_flow_logs_kms_key_arn" {
  command         = plan
  expect_failures = [var.flow_logs_kms_key_arn]

  variables {
    flow_logs_kms_key_arn = "my-key"
  }
}

run "rejects_kms_key_with_external_bucket" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    enable_flow_logs        = true
    flow_logs_s3_bucket_arn = "arn:aws:s3:::existing-flow-logs"
    flow_logs_kms_key_arn   = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }
}

run "flow_logs_to_cloudwatch" {
  command = plan

  variables {
    enable_flow_logs                    = true
    flow_logs_destination_type          = "cloud-watch-logs"
    flow_logs_cloudwatch_retention_days = 90
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0
    error_message = "no S3 bucket should be created for the CloudWatch destination"
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 90
    error_message = "the log group should honor flow_logs_cloudwatch_retention_days"
  }

  assert {
    condition     = length(aws_iam_role.flow_logs_cloudwatch) == 1 && length(aws_iam_role_policy.flow_logs_cloudwatch) == 1
    error_message = "a delivery role and policy should be created for CloudWatch Logs"
  }

  assert {
    condition     = toset([for c in data.aws_iam_policy_document.flow_logs_cloudwatch_assume[0].statement[0].condition : c.variable]) == toset(["aws:SourceAccount", "aws:SourceArn"])
    error_message = "the delivery role trust policy should be scoped with aws:SourceAccount and aws:SourceArn"
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination_type == "cloud-watch-logs" && length(aws_flow_log.this[0].destination_options) == 0
    error_message = "the flow log should target CloudWatch Logs without S3 destination options"
  }
}

run "rejects_bad_flow_logs_destination_type" {
  command         = plan
  expect_failures = [var.flow_logs_destination_type]

  variables {
    flow_logs_destination_type = "kinesis"
  }
}

run "rejects_bad_cloudwatch_retention" {
  command         = plan
  expect_failures = [var.flow_logs_cloudwatch_retention_days]

  variables {
    flow_logs_cloudwatch_retention_days = 42
  }
}

run "rejects_invalid_cloudwatch_kms_key_arn" {
  command         = plan
  expect_failures = [var.flow_logs_cloudwatch_kms_key_arn]

  variables {
    flow_logs_cloudwatch_kms_key_arn = "alias/logs"
  }
}

run "rejects_cloudwatch_with_s3_bucket_arn" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    enable_flow_logs           = true
    flow_logs_destination_type = "cloud-watch-logs"
    flow_logs_s3_bucket_arn    = "arn:aws:s3:::existing-flow-logs"
  }
}

###############################################################################
# VPC endpoint policies
###############################################################################

run "endpoint_policies_and_private_dns" {
  command = plan

  variables {
    interface_endpoints = ["sts", "ssm"]
    interface_endpoint_options = {
      sts = {
        policy              = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sts:AssumeRole\",\"Resource\":\"*\"}]}"
        private_dns_enabled = false
      }
    }
    s3_gateway_endpoint_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = aws_vpc_endpoint.interface["sts"].private_dns_enabled == false
    error_message = "private_dns_enabled should be configurable per endpoint"
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].private_dns_enabled == true
    error_message = "endpoints without options should keep private DNS enabled"
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.interface["sts"].policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "the interface endpoint policy should be applied"
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.s3_gateway[0].policy).Statement[0].Action == "s3:GetObject"
    error_message = "the S3 gateway endpoint policy should be applied"
  }
}

run "rejects_invalid_interface_endpoint_policy" {
  command         = plan
  expect_failures = [var.interface_endpoint_options]

  variables {
    interface_endpoints = ["sts"]
    interface_endpoint_options = {
      sts = { policy = "{not json" }
    }
  }
}

run "rejects_invalid_s3_gateway_endpoint_policy" {
  command         = plan
  expect_failures = [var.s3_gateway_endpoint_policy]

  variables {
    s3_gateway_endpoint_policy = "{not json"
  }
}

run "rejects_endpoint_options_for_unlisted_endpoint" {
  command         = plan
  expect_failures = [aws_vpc.this]

  variables {
    interface_endpoints = ["sts"]
    interface_endpoint_options = {
      ssm = { private_dns_enabled = false }
    }
  }
}
