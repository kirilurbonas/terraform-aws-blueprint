# vpc

Production-grade AWS VPC with public/private subnets, NAT gateways, and optional
VPC Flow Logs to S3.

## Features

- VPC with configurable CIDR (`/16`–`/24`), DNS hostnames and resolution enabled
- Public and private subnets across N AZs (subnets carved with `cidrsubnet`)
- Subnets tagged for native Kubernetes ELB discovery (`kubernetes.io/role/elb`,
  `kubernetes.io/role/internal-elb`)
- Internet Gateway and route tables
- NAT Gateway topology selectable: `single` (cost-optimized) or `per_az` (HA)
- VPC Flow Logs to S3 with lifecycle transitions (IA → Glacier → expiry)
- Module-managed flow-log buckets are hardened with ACLs disabled, TLS-only
  access, and the AWS log-delivery bucket policy pre-wired
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

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix applied to all named resources. |
| `environment` | `string` | — | yes | One of `dev`, `staging`, `prod`. |
| `project` | `string` | — | yes | Project tag for cost allocation. |
| `vpc_cidr` | `string` | — | yes | VPC CIDR block, `/16`–`/24`. |
| `availability_zones` | `list(string)` | — | yes | AZs to deploy into (≥ 2). |
| `enable_nat_gateway` | `bool` | `true` | no | Provision NAT gateways. |
| `nat_gateway_mode` | `string` | `"per_az"` | no | `single` or `per_az`. |
| `enable_flow_logs` | `bool` | `true` | no | Enable VPC Flow Logs to S3. |
| `flow_logs_s3_bucket_arn` | `string` | `null` | no | Pre-existing bucket ARN; else module-managed. |
| `flow_logs_retention_days` | `number` | `365` | no | Days before flow log objects expire. |
| `flow_logs_file_format` | `string` | `"plain-text"` | no | Flow log file format: `plain-text` or `parquet`. |
| `flow_logs_hive_compatible_partitions` | `bool` | `false` | no | Use hive-compatible S3 prefixes for flow logs. |
| `flow_logs_per_hour_partition` | `bool` | `false` | no | Partition flow logs by hour instead of day. |
| `enable_s3_gateway_endpoint` | `bool` | `true` | no | S3 gateway endpoint on the private route tables (free, saves NAT egress). |
| `interface_endpoints` | `list(string)` | `[]` | no | AWS service short names (e.g. `ecr.api`, `sts`) to expose as interface endpoints in private subnets. |
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
| `internet_gateway_id` | Internet Gateway ID. |
| `nat_gateway_ids` | NAT Gateway IDs. |
| `nat_gateway_public_ips` | NAT public IPs. |
| `public_route_table_id` | Public route table ID. |
| `private_route_table_ids` | Private route table IDs (per AZ). |
| `flow_logs_bucket_arn` | Module-managed flow log bucket ARN, if any. |
| `availability_zones` | AZs the module deployed into. |
| `s3_gateway_endpoint_id` | ID of the S3 gateway endpoint, or `null` when disabled. |
| `interface_endpoint_ids` | Map of interface endpoint service short name → endpoint ID. |

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs auto-generates the full requirements / providers / resources / inputs / outputs tables here when the pre-commit hook runs. The hand-written inputs/outputs tables above stay; this block is appended below them. -->
<!-- END_TF_DOCS -->
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.46.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
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
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of AZs to deploy subnets into. At least 2 required for production HA. | `list(string)` | n/a | yes |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC Flow Logs. Logs go to the bucket at `flow_logs_s3_bucket_arn` if set, otherwise to a module-managed bucket. | `bool` | `true` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Whether to provision NAT gateways for private subnet egress. | `bool` | `true` | no |
| <a name="input_enable_s3_gateway_endpoint"></a> [enable\_s3\_gateway\_endpoint](#input\_enable\_s3\_gateway\_endpoint) | Provision a gateway endpoint for S3 (free, attaches to private route tables, saves NAT egress). | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (e.g. dev, staging, prod). Drives tagging and lifecycle behavior. | `string` | n/a | yes |
| <a name="input_flow_logs_file_format"></a> [flow\_logs\_file\_format](#input\_flow\_logs\_file\_format) | S3 file format for VPC flow logs: plain-text or parquet. | `string` | `"plain-text"` | no |
| <a name="input_flow_logs_hive_compatible_partitions"></a> [flow\_logs\_hive\_compatible\_partitions](#input\_flow\_logs\_hive\_compatible\_partitions) | Whether to use hive-compatible S3 key prefixes for VPC flow log delivery. | `bool` | `false` | no |
| <a name="input_flow_logs_per_hour_partition"></a> [flow\_logs\_per\_hour\_partition](#input\_flow\_logs\_per\_hour\_partition) | Whether to partition VPC flow log objects by hour instead of day. | `bool` | `false` | no |
| <a name="input_flow_logs_retention_days"></a> [flow\_logs\_retention\_days](#input\_flow\_logs\_retention\_days) | Number of days to retain VPC flow logs in S3 before expiration. | `number` | `365` | no |
| <a name="input_flow_logs_s3_bucket_arn"></a> [flow\_logs\_s3\_bucket\_arn](#input\_flow\_logs\_s3\_bucket\_arn) | Optional pre-existing S3 bucket ARN for flow logs. If null, the module creates a dedicated bucket. | `string` | `null` | no |
| <a name="input_interface_endpoints"></a> [interface\_endpoints](#input\_interface\_endpoints) | Service short names (e.g. ecr.api, ecr.dkr, sts, logs, ec2) to expose as interface endpoints in the private subnets. Each one costs per-AZ + per-GB but is cheaper than NAT for chatty workloads. | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to all named resources (e.g. `platform`). | `string` | n/a | yes |
| <a name="input_nat_gateway_mode"></a> [nat\_gateway\_mode](#input\_nat\_gateway\_mode) | NAT gateway topology: `single` (one shared NAT, cost-optimized) or `per_az` (NAT in every AZ, HA). | `string` | `"per_az"` | no |
| <a name="input_project"></a> [project](#input\_project) | Project name tag applied to every resource for cost allocation. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC. Must be a valid IPv4 CIDR with prefix length /16 - /24. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | Availability zones used by the module. |
| <a name="output_flow_logs_bucket_arn"></a> [flow\_logs\_bucket\_arn](#output\_flow\_logs\_bucket\_arn) | ARN of the S3 bucket receiving VPC flow logs. Null when flow logs are disabled or a pre-existing bucket was passed in. |
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
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
