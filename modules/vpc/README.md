# vpc

Production-grade AWS VPC with public/private subnets, an optional isolated
database tier, NAT gateways, and optional VPC Flow Logs to S3 or CloudWatch Logs.

## Features

- VPC with configurable CIDR (`/16`–`/24`), DNS hostnames and resolution enabled
- Public and private subnets across N AZs (subnets carved with `cidrsubnet`;
  size configurable with `subnet_newbits` or explicit per-tier CIDR lists)
- Optional database subnet tier with its own route tables (no internet route,
  NAT optional) and an `aws_db_subnet_group`
- Optional lock-down of the VPC's default security group (all rules removed)
- Subnets tagged for native Kubernetes ELB discovery (`kubernetes.io/role/elb`,
  `kubernetes.io/role/internal-elb`)
- Internet Gateway and route tables
- NAT Gateway topology selectable: `single` (cost-optimized) or `per_az` (HA)
- VPC Flow Logs to S3 with lifecycle transitions (IA → Glacier → expiry), or to
  a module-managed CloudWatch Logs group with a scoped delivery role
- Module-managed flow-log buckets are hardened with ACLs disabled, TLS-only
  access, and the AWS log-delivery bucket policy pre-wired; SSE-KMS with a
  customer-managed key via `flow_logs_kms_key_arn`
- Optional endpoint policies and per-endpoint `private_dns_enabled` for the S3
  gateway and interface endpoints
- Optional parquet output plus hive-compatible / hourly partitioning for cheaper
  long-term analytics in Athena or Glue
- Consistent tagging: every resource gets `Name`, `Environment`, `ManagedBy`,
  `Project` plus any user-supplied tags

## Usage

```hcl
module "vpc" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/vpc?ref=v1.0.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  nat_gateway_mode = "per_az"
  enable_flow_logs = true

  tags = {
    Owner    = "platform-eng"
    CostCenter = "infra-001"
  }
}
```

### Hardened configuration

All of the following are opt-in; defaults are unchanged until v1.0.0.

```hcl
module "vpc" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/vpc?ref=v1.0.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # Strip all rules from the VPC's default security group (recommended).
  manage_default_security_group = true

  # Isolated database tier + DB subnet group for the rds module.
  enable_database_subnets = true

  # SSE-KMS on the module-managed flow-log bucket.
  flow_logs_kms_key_arn = aws_kms_key.logs.arn

  interface_endpoints = ["sts", "ecr.api", "ecr.dkr"]
  interface_endpoint_options = {
    sts = { policy = data.aws_iam_policy_document.sts_endpoint.json }
  }
}
```

## Subnet layout

By default the VPC CIDR is split into `2^subnet_newbits` equal blocks
(`subnet_newbits = 4` → sixteen /20s from a /16):

| Tier | Block index | Default (`newbits = 4`) | Max AZs |
|------|-------------|-------------------------|---------|
| public | `i` | `cidrsubnet(vpc_cidr, 4, i)` | `2^(newbits-1)` = 8 |
| private | `i + 2^(newbits-1)` | `cidrsubnet(vpc_cidr, 4, i + 8)` | 8, or `2^(newbits-2)` = 4 with the database tier carved |
| database | `i + 2^(newbits-1) + 2^(newbits-2)` | `cidrsubnet(vpc_cidr, 4, i + 12)` | `2^(newbits-2)` = 4 |

With the defaults this is exactly the pre-0.4 layout, so existing VPCs plan with
no changes. Enabling the database tier does not move the public or private
subnets; it uses the last quarter of the VPC, which the private tier only
reaches with more than 4 AZs. A plan fails with a precondition error if the AZ
count exceeds a carved tier's capacity, or if `vpc_cidr` prefix + `subnet_newbits`
is longer than /28.

`public_subnet_cidrs`, `private_subnet_cidrs` and `database_subnet_cidrs`
replace the carve for their tier and must have one entry per AZ. The module does
not check explicit lists for overlap with each other or with carved tiers; AWS
rejects overlapping subnets at apply.

Database route tables (one per AZ) never get an internet-gateway route. Set
`database_subnets_nat_access = true` to add a NAT default route (requires
`enable_nat_gateway`). The S3 gateway endpoint is attached to the database
route tables as well as the private ones.

## Flow-log encryption and destinations

**S3 with a customer-managed key.** With `flow_logs_kms_key_arn` set, the
module-managed bucket uses SSE-KMS with S3 Bucket Keys enabled. S3 bucket
policies cannot grant KMS permissions, so the key policy must allow the log
delivery service to use the key. Add this statement to the key policy:

```json
{
  "Sid": "AllowVPCFlowLogsDelivery",
  "Effect": "Allow",
  "Principal": { "Service": "delivery.logs.amazonaws.com" },
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:SourceAccount": "<account-id>" },
    "ArnLike": { "aws:SourceArn": "arn:aws:logs:<region>:<account-id>:*" }
  }
}
```

Without a key the bucket stays on SSE-S3 (AES256); that default is kept until
v1.0.0. `flow_logs_kms_key_arn` applies only to the module-managed bucket and is
rejected together with `flow_logs_s3_bucket_arn` or the CloudWatch destination.

**CloudWatch Logs.** `flow_logs_destination_type = "cloud-watch-logs"` creates
the log group `/aws/vpc-flow-logs/<name_prefix>-<environment>` (retention
`flow_logs_cloudwatch_retention_days`, optional `flow_logs_cloudwatch_kms_key_arn`)
and an IAM role for `vpc-flow-logs.amazonaws.com`. The role's trust policy is
restricted with `aws:SourceAccount` and `aws:SourceArn`, and its permissions are
scoped to that log group. If you pass a KMS key for the log group, its key
policy must allow `logs.<region>.amazonaws.com`. The S3-only settings
(`flow_logs_file_format`, partitioning, `flow_logs_retention_days`) are ignored
for this destination.

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix applied to all named resources. |
| `environment` | `string` | — | yes | One of `dev`, `staging`, `prod`. |
| `project` | `string` | — | yes | Project tag for cost allocation. |
| `vpc_cidr` | `string` | — | yes | VPC CIDR block, `/16`–`/24`. |
| `availability_zones` | `list(string)` | — | yes | AZs to deploy into (≥ 2). |
| `subnet_newbits` | `number` | `4` | no | `cidrsubnet` newbits for the carved tiers (2–12). |
| `public_subnet_cidrs` | `list(string)` | `null` | no | Explicit public CIDRs, one per AZ; overrides the carve. |
| `private_subnet_cidrs` | `list(string)` | `null` | no | Explicit private CIDRs, one per AZ; overrides the carve. |
| `enable_database_subnets` | `bool` | `false` | no | Create the isolated database subnet tier. |
| `database_subnet_cidrs` | `list(string)` | `null` | no | Explicit database CIDRs, one per AZ; overrides the carve. |
| `database_subnets_nat_access` | `bool` | `false` | no | Add a NAT default route to the database route tables. |
| `create_database_subnet_group` | `bool` | `true` | no | Create an `aws_db_subnet_group` when the database tier is enabled. |
| `manage_default_security_group` | `bool` | `false` | no | Remove all rules from the VPC's default SG. Recommended `true`. |
| `enable_nat_gateway` | `bool` | `true` | no | Provision NAT gateways. |
| `nat_gateway_mode` | `string` | `"per_az"` | no | `single` or `per_az`. |
| `enable_flow_logs` | `bool` | `true` | no | Enable VPC Flow Logs to S3. |
| `flow_logs_destination_type` | `string` | `"s3"` | no | `s3` or `cloud-watch-logs`. |
| `flow_logs_s3_bucket_arn` | `string` | `null` | no | Pre-existing bucket ARN; else module-managed. |
| `flow_logs_kms_key_arn` | `string` | `null` | no | KMS key for SSE-KMS on the module-managed bucket; null = SSE-S3. |
| `flow_logs_cloudwatch_retention_days` | `number` | `365` | no | Retention for the CloudWatch Logs flow-log group. |
| `flow_logs_cloudwatch_kms_key_arn` | `string` | `null` | no | KMS key for the CloudWatch Logs flow-log group. |
| `flow_logs_retention_days` | `number` | `365` | no | Days before flow log objects expire. |
| `flow_logs_file_format` | `string` | `"plain-text"` | no | Flow log file format: `plain-text` or `parquet`. |
| `flow_logs_hive_compatible_partitions` | `bool` | `false` | no | Use hive-compatible S3 prefixes for flow logs. |
| `flow_logs_per_hour_partition` | `bool` | `false` | no | Partition flow logs by hour instead of day. |
| `enable_s3_gateway_endpoint` | `bool` | `true` | no | S3 gateway endpoint on the private route tables (free, saves NAT egress). |
| `interface_endpoints` | `list(string)` | `[]` | no | AWS service short names (e.g. `ecr.api`, `sts`) to expose as interface endpoints in private subnets. |
| `interface_endpoint_options` | `map(object)` | `{}` | no | Per-endpoint JSON `policy` and `private_dns_enabled` (default `true`), keyed by short name. |
| `s3_gateway_endpoint_policy` | `string` | `null` | no | JSON policy for the S3 gateway endpoint. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC. |
| `vpc_arn` | ARN of the VPC. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `public_subnet_ids` | Public subnet IDs (ordered by AZ). |
| `private_subnet_ids` | Private subnet IDs (ordered by AZ). |
| `public_subnet_cidrs` | Public subnet CIDRs. |
| `private_subnet_cidrs` | Private subnet CIDRs. |
| `database_subnet_ids` | Database subnet IDs (ordered by AZ); empty when disabled. |
| `database_subnet_cidrs` | Database subnet CIDRs; empty when disabled. |
| `database_subnet_group_name` | DB subnet group name, or `null`. |
| `database_route_table_ids` | Database route table IDs (per AZ). |
| `default_security_group_id` | ID of the VPC's default security group. |
| `internet_gateway_id` | Internet Gateway ID. |
| `nat_gateway_ids` | NAT Gateway IDs. |
| `nat_gateway_public_ips` | NAT public IPs. |
| `public_route_table_id` | Public route table ID. |
| `private_route_table_ids` | Private route table IDs (per AZ). |
| `flow_logs_bucket_arn` | Module-managed flow log bucket ARN, if any. |
| `flow_logs_cloudwatch_log_group_arn` | CloudWatch Logs flow-log group ARN, if any. |
| `flow_logs_cloudwatch_iam_role_arn` | Flow-log delivery role ARN, if any. |
| `availability_zones` | AZs the module deployed into. |
| `s3_gateway_endpoint_id` | ID of the S3 gateway endpoint, or `null` when disabled. |
| `interface_endpoint_ids` | Map of interface endpoint service short name → endpoint ID. |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |



## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_db_subnet_group.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.database_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_cloudwatch_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of AZs to deploy subnets into. At least 2 required for production HA. | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (e.g. dev, staging, prod). Drives tagging and lifecycle behavior. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to all named resources (e.g. `platform`). | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name tag applied to every resource for cost allocation. | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC. Must be a valid IPv4 CIDR with prefix length /16 - /24. | `string` | n/a | yes |
| <a name="input_create_database_subnet_group"></a> [create\_database\_subnet\_group](#input\_create\_database\_subnet\_group) | Create an `aws_db_subnet_group` spanning the database subnets. Only takes effect when `enable_database_subnets = true`. | `bool` | `true` | no |
| <a name="input_database_subnet_cidrs"></a> [database\_subnet\_cidrs](#input\_database\_subnet\_cidrs) | Explicit database subnet CIDRs, one per entry in `availability_zones` (same order). Requires `enable_database_subnets = true`. Overrides the `subnet_newbits` carve for this tier. | `list(string)` | `null` | no |
| <a name="input_database_subnets_nat_access"></a> [database\_subnets\_nat\_access](#input\_database\_subnets\_nat\_access) | Add a default route via the NAT gateway(s) to the database route tables. Off by default: database subnets have no route to the internet at all. Requires `enable_database_subnets` and `enable_nat_gateway`. | `bool` | `false` | no |
| <a name="input_enable_database_subnets"></a> [enable\_database\_subnets](#input\_enable\_database\_subnets) | Create a database subnet per AZ with its own route tables that have no internet gateway route, so RDS and similar services stop sharing the application private subnets. | `bool` | `false` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC Flow Logs. Logs go to the bucket at `flow_logs_s3_bucket_arn` if set, otherwise to a module-managed bucket. | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Whether to provision NAT gateways for private subnet egress. | `bool` | `true` | no |
| <a name="input_enable_s3_gateway_endpoint"></a> [enable\_s3\_gateway\_endpoint](#input\_enable\_s3\_gateway\_endpoint) | Provision a gateway endpoint for S3 (free, attaches to private route tables, saves NAT egress). | `bool` | `true` | no |
| <a name="input_flow_logs_cloudwatch_kms_key_arn"></a> [flow\_logs\_cloudwatch\_kms\_key\_arn](#input\_flow\_logs\_cloudwatch\_kms\_key\_arn) | Optional KMS key ARN for the module-managed CloudWatch Logs flow-log group. The key policy must allow the regional `logs.<region>.amazonaws.com` service principal to use it. | `string` | `null` | no |
| <a name="input_flow_logs_cloudwatch_retention_days"></a> [flow\_logs\_cloudwatch\_retention\_days](#input\_flow\_logs\_cloudwatch\_retention\_days) | Retention for the module-managed CloudWatch Logs flow-log group. Must be a value CloudWatch Logs accepts. Only used when `flow_logs_destination_type = "cloud-watch-logs"`. | `number` | `365` | no |
| <a name="input_flow_logs_destination_type"></a> [flow\_logs\_destination\_type](#input\_flow\_logs\_destination\_type) | Flow log destination: `s3` (module-managed or `flow_logs_s3_bucket_arn` bucket) or `cloud-watch-logs` (module-managed log group plus an IAM delivery role). | `string` | `"s3"` | no |
| <a name="input_flow_logs_file_format"></a> [flow\_logs\_file\_format](#input\_flow\_logs\_file\_format) | S3 file format for VPC flow logs: plain-text or parquet. | `string` | `"plain-text"` | no |
| <a name="input_flow_logs_hive_compatible_partitions"></a> [flow\_logs\_hive\_compatible\_partitions](#input\_flow\_logs\_hive\_compatible\_partitions) | Whether to use hive-compatible S3 key prefixes for VPC flow log delivery. | `bool` | `false` | no |
| <a name="input_flow_logs_kms_key_arn"></a> [flow\_logs\_kms\_key\_arn](#input\_flow\_logs\_kms\_key\_arn) | KMS key ARN for SSE-KMS on the module-managed flow-log bucket (S3 Bucket Key enabled). Null keeps SSE-S3 (AES256). The key policy must allow `delivery.logs.amazonaws.com` to use the key; see the README for the statement. | `string` | `null` | no |
| <a name="input_flow_logs_per_hour_partition"></a> [flow\_logs\_per\_hour\_partition](#input\_flow\_logs\_per\_hour\_partition) | Whether to partition VPC flow log objects by hour instead of day. | `bool` | `false` | no |
| <a name="input_flow_logs_retention_days"></a> [flow\_logs\_retention\_days](#input\_flow\_logs\_retention\_days) | Number of days to retain VPC flow logs in S3 before expiration. | `number` | `365` | no |
| <a name="input_flow_logs_s3_bucket_arn"></a> [flow\_logs\_s3\_bucket\_arn](#input\_flow\_logs\_s3\_bucket\_arn) | Optional pre-existing S3 bucket ARN for flow logs. If null, the module creates a dedicated bucket. | `string` | `null` | no |
| <a name="input_interface_endpoint_options"></a> [interface\_endpoint\_options](#input\_interface\_endpoint\_options) | Per-endpoint settings keyed by a service short name from `interface_endpoints`: an optional JSON endpoint `policy` (null = AWS default full access) and `private_dns_enabled` (default true). Endpoints without an entry keep the defaults. | <pre>map(object({<br/>    policy              = optional(string)<br/>    private_dns_enabled = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_interface_endpoints"></a> [interface\_endpoints](#input\_interface\_endpoints) | Service short names (e.g. ecr.api, ecr.dkr, sts, logs, ec2) to expose as interface endpoints in the private subnets. Each one costs per-AZ + per-GB but is cheaper than NAT for chatty workloads. | `list(string)` | `[]` | no |
| <a name="input_manage_default_security_group"></a> [manage\_default\_security\_group](#input\_manage\_default\_security\_group) | Adopt the VPC's default security group and remove all of its rules (CIS AWS 5.4). Recommended `true`; defaults to `false` for backwards compatibility and will flip at v1.0.0. Enabling it on an existing VPC revokes the default SG's rules, which breaks anything relying on them. | `bool` | `false` | no |
| <a name="input_nat_gateway_mode"></a> [nat\_gateway\_mode](#input\_nat\_gateway\_mode) | NAT gateway topology: `single` (one shared NAT, cost-optimized) or `per_az` (NAT in every AZ, HA). | `string` | `"per_az"` | no |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | Explicit private subnet CIDRs, one per entry in `availability_zones` (same order). Overrides the `subnet_newbits` carve for this tier. Overlap with other tiers is not checked by the module; AWS rejects it at apply. | `list(string)` | `null` | no |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | Explicit public subnet CIDRs, one per entry in `availability_zones` (same order). Overrides the `subnet_newbits` carve for this tier. Overlap with other tiers is not checked by the module; AWS rejects it at apply. | `list(string)` | `null` | no |
| <a name="input_s3_gateway_endpoint_policy"></a> [s3\_gateway\_endpoint\_policy](#input\_s3\_gateway\_endpoint\_policy) | Optional JSON endpoint policy for the S3 gateway endpoint. Null leaves the AWS default (full access). | `string` | `null` | no |
| <a name="input_subnet_newbits"></a> [subnet\_newbits](#input\_subnet\_newbits) | Bits added to the VPC prefix for each carved subnet (`cidrsubnet` newbits). Public subnets take the first half of the resulting blocks, private the second half, and the database tier (when enabled) the last quarter. The default 4 gives /20s from a /16 and fits 8 AZs, or 4 AZs with the database tier carved. Ignored for any tier whose explicit `*_subnet_cidrs` list is set. | `number` | `4` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | Availability zones used by the module. |
| <a name="output_database_route_table_ids"></a> [database\_route\_table\_ids](#output\_database\_route\_table\_ids) | List of database route table IDs (one per AZ). Empty when `enable_database_subnets = false`. |
| <a name="output_database_subnet_cidrs"></a> [database\_subnet\_cidrs](#output\_database\_subnet\_cidrs) | CIDR blocks of the database subnets. Empty when `enable_database_subnets = false`. |
| <a name="output_database_subnet_group_name"></a> [database\_subnet\_group\_name](#output\_database\_subnet\_group\_name) | Name of the RDS DB subnet group spanning the database subnets, or null when not created. |
| <a name="output_database_subnet_ids"></a> [database\_subnet\_ids](#output\_database\_subnet\_ids) | List of database subnet IDs, ordered to match `availability_zones`. Empty when `enable_database_subnets = false`. |
| <a name="output_default_security_group_id"></a> [default\_security\_group\_id](#output\_default\_security\_group\_id) | ID of the VPC's default security group (rules stripped when `manage_default_security_group = true`). |
| <a name="output_flow_logs_bucket_arn"></a> [flow\_logs\_bucket\_arn](#output\_flow\_logs\_bucket\_arn) | ARN of the S3 bucket receiving VPC flow logs. Null when flow logs are disabled or a pre-existing bucket was passed in. |
| <a name="output_flow_logs_cloudwatch_iam_role_arn"></a> [flow\_logs\_cloudwatch\_iam\_role\_arn](#output\_flow\_logs\_cloudwatch\_iam\_role\_arn) | ARN of the IAM role VPC Flow Logs assumes to write to CloudWatch Logs. Null unless `flow_logs_destination_type = "cloud-watch-logs"`. |
| <a name="output_flow_logs_cloudwatch_log_group_arn"></a> [flow\_logs\_cloudwatch\_log\_group\_arn](#output\_flow\_logs\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch Logs group receiving VPC flow logs. Null unless `flow_logs_destination_type = "cloud-watch-logs"`. |
| <a name="output_interface_endpoint_ids"></a> [interface\_endpoint\_ids](#output\_interface\_endpoint\_ids) | Map of interface endpoint service short name -> endpoint ID. |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | ID of the Internet Gateway. |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | List of NAT Gateway IDs. Empty when `enable_nat_gateway = false`. |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | Elastic IPs attached to the NAT gateways. |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | List of private route table IDs (one per AZ). |
| <a name="output_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#output\_private\_subnet\_cidrs) | CIDR blocks of the private subnets. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs, ordered to match `availability_zones`. |
| <a name="output_public_route_table_id"></a> [public\_route\_table\_id](#output\_public\_route\_table\_id) | ID of the public route table. |
| <a name="output_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#output\_public\_subnet\_cidrs) | CIDR blocks of the public subnets. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs, ordered to match `availability_zones`. |
| <a name="output_s3_gateway_endpoint_id"></a> [s3\_gateway\_endpoint\_id](#output\_s3\_gateway\_endpoint\_id) | ID of the S3 gateway endpoint, or null when disabled. |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | ARN of the VPC. |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | CIDR block of the VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC. |
<!-- END_TF_DOCS -->
