# example: simple-vpc

Smallest possible call into the `vpc` module — three AZs, a single shared NAT
gateway, no flow logs. Useful for spinning up a sandbox VPC.

## Usage

```bash
cd examples/simple-vpc
terraform init
terraform apply
```

To target a non-default region or CIDR:

```bash
terraform apply -var region=eu-west-1 -var vpc_cidr=10.50.0.0/16
```

To use a shared remote state, uncomment the `backend "s3"` block in
[backend.tf](backend.tf) and re-run `terraform init`.

## Approximate monthly cost

| Item | Cost (us-east-1) |
|------|------------------|
| 1 NAT gateway | ~$32 |
| Elastic IP (attached) | $0 |
| VPC + subnets + route tables | $0 |
| **Total** | **~$32/mo + NAT data processing** |

Run `terraform destroy` when you're done sandboxing.
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.46.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../../modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag for the example. | `string` | `"dev"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the example. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the example VPC. | `string` | `"10.10.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the demo VPC. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
