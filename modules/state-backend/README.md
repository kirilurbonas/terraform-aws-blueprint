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
