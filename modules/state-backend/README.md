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
- Optional S3-native locking (`enable_dynamodb_lock = false`) — no DynamoDB
  table, `use_lockfile = true` in the emitted backend config
- Optional server access logging to a separate bucket
- Optional replication to a DR bucket, with a module-created role scoped to
  the two buckets and the KMS keys involved (delete markers are not
  replicated)

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

## S3-native locking

Terraform 1.10 added S3-native state locking (`use_lockfile = true`): the lock
is a `<key>.tflock` object written next to the state with a conditional PUT,
so no DynamoDB table is needed. Terraform 1.11 deprecates the S3 backend's
`dynamodb_table` argument.

The module still creates the DynamoDB table by default
(`enable_dynamodb_lock = true`), and `backend_config_hcl` is unchanged in that
mode. The default flips at v1.0.0. To opt in now:

```hcl
module "tfstate" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/state-backend?ref=v0.4.0"

  environment          = "prod"
  project              = "blueprint"
  bucket_name          = "tfstate-blueprint-prod-111122223333"
  enable_dynamodb_lock = false
}
```

`backend_config_hcl` then emits:

```hcl
bucket       = "tfstate-blueprint-prod-111122223333"
key          = "<stack-name>/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
```

Migrating an existing backend:

1. Every stack that uses the backend must run Terraform >= 1.10.
2. In each downstream stack, replace `dynamodb_table = ...` with
   `use_lockfile = true` and run `terraform init -reconfigure`. Both can be set
   during the transition — Terraform then takes both locks.
3. Callers need `s3:PutObject` and `s3:DeleteObject` on
   `<bucket>/<key>.tflock` in addition to their existing state permissions.
4. Set `enable_dynamodb_lock = false` here. The lock table has
   `deletion_protection_enabled = true`, so the plan to destroy it fails until
   protection is turned off. To keep the table and only stop managing it, run
   `terraform state rm 'module.tfstate.aws_dynamodb_table.lock[0]'` first.

Upgrading from v0.3.x needs no action: the lock table moved to
`aws_dynamodb_table.lock[0]` and a `moved` block migrates the existing state
entry.

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `bucket_name` | `string` | — | yes | Globally unique S3 bucket name. |
| `lock_table_name` | `string` | `null` | when DynamoDB lock | DynamoDB table name. |
| `enable_dynamodb_lock` | `bool` | `true` | no | Create the lock table; `false` = S3-native locking. |
| `kms_key_arn` | `string` | `null` | no | CMK for state encryption. |
| `noncurrent_version_expiration_days` | `number` | `365` | no | Age out old state versions. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |
| `access_logging` | `object` | `null` | no | Server access logging target bucket / prefix. |
| `replication` | `object` | `null` | no | DR replication destination, replica KMS key, optional role. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` / `bucket_arn` | State bucket. |
| `lock_table_name` / `lock_table_arn` | Lock table. `null` with S3-native locking. |
| `backend_config_hcl` | Ready-to-paste backend block body. |
| `replication_role_arn` | Replication role. `null` when replication is off. |

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
| [aws_dynamodb_table.lock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_replication_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_replication_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.replication_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | S3 bucket name (globally unique) that will hold Terraform state. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag. | `string` | n/a | yes |
| <a name="input_access_logging"></a> [access\_logging](#input\_access\_logging) | Server access logging for the state bucket. target\_prefix = null uses "<bucket\_name>/". Null = no access logging. | <pre>object({<br/>    target_bucket = string<br/>    target_prefix = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_enable_dynamodb_lock"></a> [enable\_dynamodb\_lock](#input\_enable\_dynamodb\_lock) | Create the DynamoDB lock table and emit `dynamodb_table` in backend\_config\_hcl. Set false to use S3-native locking (`use_lockfile = true`, Terraform >= 1.10) with no table; Terraform 1.11 deprecates DynamoDB locking. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Optional customer-managed KMS key for state encryption (S3 + DynamoDB). Null = AWS-managed. | `string` | `null` | no |
| <a name="input_lock_table_name"></a> [lock\_table\_name](#input\_lock\_table\_name) | DynamoDB table name for state locks. Required when enable\_dynamodb\_lock = true; ignored otherwise. | `string` | `null` | no |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Days to retain old state versions before lifecycle expiration. | `number` | `365` | no |
| <a name="input_replication"></a> [replication](#input\_replication) | Replicate state objects to a DR bucket (typically in another region). The<br/>destination bucket must already exist with versioning enabled. role\_arn =<br/>null creates a role scoped to the two buckets and the KMS keys involved.<br/>destination\_kms\_key\_arn is required when kms\_key\_arn is set. Delete markers<br/>are not replicated. Null = no replication. | <pre>object({<br/>    destination_bucket_arn  = string<br/>    destination_kms_key_arn = optional(string)<br/>    role_arn                = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_config_hcl"></a> [backend\_config\_hcl](#output\_backend\_config\_hcl) | Ready-to-paste `terraform { backend "s3" { ... } }` body for downstream stacks. Uses `dynamodb_table` locking, or `use_lockfile = true` (Terraform >= 1.10) when enable\_dynamodb\_lock = false. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the state bucket. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the state bucket. |
| <a name="output_lock_table_arn"></a> [lock\_table\_arn](#output\_lock\_table\_arn) | ARN of the DynamoDB lock table. Null when enable\_dynamodb\_lock = false. |
| <a name="output_lock_table_name"></a> [lock\_table\_name](#output\_lock\_table\_name) | Name of the DynamoDB lock table. Null when enable\_dynamodb\_lock = false. |
| <a name="output_replication_role_arn"></a> [replication\_role\_arn](#output\_replication\_role\_arn) | IAM role S3 uses to replicate state — the module-created role, or replication.role\_arn when supplied. Null when replication is disabled. |
<!-- END_TF_DOCS -->
