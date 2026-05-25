# s3-secure

S3 bucket with a secure-by-default posture: public access blocked, ACLs
disabled, versioning on, encryption on, lifecycle rules in place, and a bucket
policy that denies plaintext (HTTP) requests and unencrypted uploads.

## Features

- All four `BlockPublicAccess` settings on by default
- `BucketOwnerEnforced` ownership (ACLs disabled — the AWS-recommended posture)
- Versioning enabled by default
- SSE-S3 (`AES256`) by default; KMS supported with `bucket_key_enabled = true`
  to keep per-object KMS cost under control
- Lifecycle rule with optional tiering to STANDARD_IA / GLACIER, expiration,
  noncurrent-version tiering/expiration, and 7-day cleanup of stale multipart
  uploads
- Optional access logging to a separate bucket
- Optional CORS rules
- Bucket policy denies:
  - any request not over TLS (`aws:SecureTransport = false`)
  - `PutObject` without `x-amz-server-side-encryption` (configurable)
- Extra bucket-policy statements can be appended by the caller

## Usage

```hcl
module "artifacts" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/s3-secure?ref=v1.0.0"

  environment        = "prod"
  project            = "blueprint"
  bucket_name_prefix = "blueprint-artifacts-"

  sse_algorithm = "aws:kms"
  kms_key_arn   = aws_kms_key.artifacts.arn

  transition_to_ia_days       = 30
  transition_to_glacier_days  = 180
  expiration_days             = 730
  noncurrent_version_expiration_days = 90

  cors_rules = [
    {
      allowed_methods = ["GET"]
      allowed_origins = ["https://app.example.com"]
      max_age_seconds = 3600
    },
  ]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |
| `bucket_name` | `string` | `null` | one-of | Exact bucket name. |
| `bucket_name_prefix` | `string` | `null` | one-of | Prefix for a generated name. |
| `force_destroy` | `bool` | `false` | no | Allow `destroy` on a non-empty bucket. |
| `block_public_acls` | `bool` | `true` | no | PAB setting. |
| `block_public_policy` | `bool` | `true` | no | PAB setting. |
| `ignore_public_acls` | `bool` | `true` | no | PAB setting. |
| `restrict_public_buckets` | `bool` | `true` | no | PAB setting. |
| `versioning_enabled` | `bool` | `true` | no | Object versioning. |
| `sse_algorithm` | `string` | `"AES256"` | no | `AES256` or `aws:kms`. |
| `kms_key_arn` | `string` | `null` | when KMS | KMS key ARN. |
| `enable_lifecycle_rules` | `bool` | `true` | no | Apply the lifecycle rule. |
| `lifecycle_prefix` | `string` | `""` | no | Prefix the lifecycle rule applies to. |
| `transition_to_ia_days` | `number` | `30` | no | Days → STANDARD_IA. |
| `transition_to_glacier_days` | `number` | `90` | no | Days → GLACIER. |
| `expiration_days` | `number` | `null` | no | Current-version expiration. |
| `noncurrent_version_transition_days` | `number` | `30` | no | Noncurrent → GLACIER. |
| `noncurrent_version_expiration_days` | `number` | `365` | no | Noncurrent expiration. |
| `access_logging_target_bucket` | `string` | `null` | no | Logging target bucket. |
| `access_logging_target_prefix` | `string` | `null` | no | Logging target prefix. |
| `cors_rules` | `list(object)` | `[]` | no | CORS rules. |
| `deny_unencrypted_object_uploads` | `bool` | `true` | no | Add the encryption-required policy statement. |
| `extra_policy_statements` | `list(object)` | `[]` | no | Caller-supplied bucket-policy statements. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Bucket name. |
| `bucket_arn` | Bucket ARN. |
| `bucket_domain_name` | Legacy domain name. |
| `bucket_regional_domain_name` | Regional domain name. |
| `bucket_hosted_zone_id` | Route53 hosted zone ID for the region. |

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs auto-generates the full requirements / providers / resources / inputs / outputs tables here when the pre-commit hook runs. The hand-written inputs/outputs tables above stay; this block is appended below them. -->
<!-- END_TF_DOCS -->
