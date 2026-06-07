# state-backend

S3 bucket + DynamoDB table for a Terraform remote backend. Run this once in a
bootstrap stack, then every downstream stack can use the printed
`backend_config_hcl` value.

## Features

- S3 bucket with public access blocked, ACLs disabled
  (`BucketOwnerEnforced`), versioning on, SSE on, and a TLS-only bucket policy
- Lifecycle rule that abort-cancels stale multipart uploads and ages out old
  state versions
- DynamoDB lock table with `PAY_PER_REQUEST` billing, point-in-time recovery,
  server-side encryption, and `deletion_protection_enabled = true`
- Optional customer-managed KMS key for both S3 SSE and DynamoDB SSE

## Bootstrap pattern

State for a backend bootstrap stack lives locally — that's expected. Once the
bucket and table exist, downstream stacks point at them.

```hcl
module "tfstate" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/state-backend?ref=v0.2.0"

  environment     = "prod"
  project         = "blueprint"
  bucket_name     = "tfstate-blueprint-prod-111122223333"
  lock_table_name = "tfstate-blueprint-prod-locks"
}

output "backend_config" {
  value = module.tfstate.backend_config_hcl
}
```

Then in every other stack:

```hcl
terraform {
  backend "s3" {
    bucket         = "tfstate-blueprint-prod-111122223333"
    key            = "platform-vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tfstate-blueprint-prod-locks"
    encrypt        = true
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `bucket_name` | `string` | — | yes | Globally unique S3 bucket name. |
| `lock_table_name` | `string` | — | yes | DynamoDB table name. |
| `kms_key_arn` | `string` | `null` | no | CMK for state encryption. |
| `noncurrent_version_expiration_days` | `number` | `365` | no | Age out old state versions. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` / `bucket_arn` | State bucket. |
| `lock_table_name` / `lock_table_arn` | Lock table. |
| `backend_config_hcl` | Ready-to-paste backend block body. |

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
| [aws_dynamodb_table.lock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | S3 bucket name (globally unique) that will hold Terraform state. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag. | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Optional customer-managed KMS key for state encryption (S3 + DynamoDB). Null = AWS-managed. | `string` | `null` | no |
| <a name="input_lock_table_name"></a> [lock\_table\_name](#input\_lock\_table\_name) | DynamoDB table name for state locks. | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Days to retain old state versions before lifecycle expiration. | `number` | `365` | no |
| <a name="input_project"></a> [project](#input\_project) | Project tag. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_config_hcl"></a> [backend\_config\_hcl](#output\_backend\_config\_hcl) | Ready-to-paste `terraform { backend "s3" { ... } }` body for downstream stacks. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the state bucket. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the state bucket. |
| <a name="output_lock_table_arn"></a> [lock\_table\_arn](#output\_lock\_table\_arn) | ARN of the DynamoDB lock table. |
| <a name="output_lock_table_name"></a> [lock\_table\_name](#output\_lock\_table\_name) | Name of the DynamoDB lock table. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
