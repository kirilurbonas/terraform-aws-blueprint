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
