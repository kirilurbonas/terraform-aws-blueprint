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
  - `PutObject` with the wrong encryption mode, and in KMS mode, the wrong key
- Extra bucket-policy statements can be appended by the caller
- Optional Object Lock default retention (GOVERNANCE / COMPLIANCE)
- Optional replication to another bucket, with a module-created role scoped to
  the two buckets and the KMS keys involved, or a caller-supplied role.
  SSE-KMS objects are opted in automatically when the bucket uses KMS
- Optional EventBridge notifications
- Optional Intelligent-Tiering Archive / Deep Archive access tiers

## Object Lock

Object Lock is enabled through `aws_s3_bucket_object_lock_configuration`
rather than the bucket's `object_lock_enabled` argument, which would force
replacement of an existing bucket. It requires versioning, and it cannot be
turned off once enabled — removing `object_lock` from the configuration stops
managing the default retention but leaves Object Lock on. `COMPLIANCE` mode
retention cannot be shortened or bypassed by any principal, including the
account root user.

```hcl
  object_lock = {
    mode = "GOVERNANCE"
    days = 30
  }
```

## Replication

The destination bucket must already exist with versioning enabled; the module
does not create it, so no provider alias is needed for a cross-region
destination. When the source bucket uses `aws:kms`, `destination_kms_key_arn`
is required.

```hcl
  replication = {
    destination_bucket_arn  = "arn:aws:s3:::blueprint-artifacts-replica"
    destination_kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/..."
    storage_class           = "STANDARD_IA"
  }
```

Replication applies to objects written after it is enabled. Use S3 Batch
Replication for existing objects. With `object_lock` set on the source, the
destination bucket needs Object Lock enabled as well.

## EventBridge and Intelligent-Tiering

`enable_eventbridge_notifications = true` makes the module own the bucket's
notification configuration (`aws_s3_bucket_notification`). Do not also manage
SNS / SQS / Lambda notifications for the same bucket elsewhere.

`intelligent_tiering` configurations act only on objects already in the
`INTELLIGENT_TIERING` storage class — they add the opt-in archive tiers, they
do not move objects into the class.

```hcl
  intelligent_tiering = {
    archive-all = {
      archive_access_days      = 90
      deep_archive_access_days = 180
    }
  }
```

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
| `object_lock` | `object` | `null` | no | Object Lock mode and default retention (days or years). |
| `replication` | `object` | `null` | no | Replication destination, storage class, replica KMS key, role, delete markers. |
| `enable_eventbridge_notifications` | `bool` | `false` | no | Send bucket events to EventBridge. |
| `intelligent_tiering` | `map(object)` | `{}` | no | Intelligent-Tiering archive configurations. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Bucket name. |
| `bucket_arn` | Bucket ARN. |
| `bucket_domain_name` | Legacy domain name. |
| `bucket_regional_domain_name` | Regional domain name. |
| `bucket_hosted_zone_id` | Route53 hosted zone ID for the region. |
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
| [aws_iam_role.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_cors_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_cors_configuration) | resource |
| [aws_s3_bucket_intelligent_tiering_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_intelligent_tiering_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_notification.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_object_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_replication_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_replication_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.replication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.replication_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | n/a | yes |
| <a name="input_access_logging_target_bucket"></a> [access\_logging\_target\_bucket](#input\_access\_logging\_target\_bucket) | Optional bucket name to receive server access logs. | `string` | `null` | no |
| <a name="input_access_logging_target_prefix"></a> [access\_logging\_target\_prefix](#input\_access\_logging\_target\_prefix) | Key prefix in the target bucket for access log objects. | `string` | `null` | no |
| <a name="input_block_public_acls"></a> [block\_public\_acls](#input\_block\_public\_acls) | Block public ACLs. | `bool` | `true` | no |
| <a name="input_block_public_policy"></a> [block\_public\_policy](#input\_block\_public\_policy) | Block public bucket policies. | `bool` | `true` | no |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Exact bucket name. Mutually exclusive with bucket\_name\_prefix. | `string` | `null` | no |
| <a name="input_bucket_name_prefix"></a> [bucket\_name\_prefix](#input\_bucket\_name\_prefix) | Prefix used to generate a unique bucket name when bucket\_name is not set. | `string` | `null` | no |
| <a name="input_cors_rules"></a> [cors\_rules](#input\_cors\_rules) | List of CORS rules. Empty list disables CORS. | <pre>list(object({<br/>    allowed_methods = list(string)<br/>    allowed_origins = list(string)<br/>    allowed_headers = optional(list(string))<br/>    expose_headers  = optional(list(string))<br/>    max_age_seconds = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_deny_unencrypted_object_uploads"></a> [deny\_unencrypted\_object\_uploads](#input\_deny\_unencrypted\_object\_uploads) | Deny PutObject calls that don't request server-side encryption. | `bool` | `true` | no |
| <a name="input_enable_eventbridge_notifications"></a> [enable\_eventbridge\_notifications](#input\_enable\_eventbridge\_notifications) | Send all bucket events to Amazon EventBridge. The module then owns the bucket's notification configuration; do not also manage SNS / SQS / Lambda notifications for this bucket elsewhere. | `bool` | `false` | no |
| <a name="input_enable_lifecycle_rules"></a> [enable\_lifecycle\_rules](#input\_enable\_lifecycle\_rules) | Apply the module's lifecycle rule. | `bool` | `true` | no |
| <a name="input_expiration_days"></a> [expiration\_days](#input\_expiration\_days) | Expire current objects after N days. Null = never. | `number` | `null` | no |
| <a name="input_extra_policy_statements"></a> [extra\_policy\_statements](#input\_extra\_policy\_statements) | Additional bucket-policy statements merged in (e.g. cross-account read access). | <pre>list(object({<br/>    sid       = optional(string)<br/>    effect    = string<br/>    actions   = list(string)<br/>    resources = list(string)<br/>    principals = optional(list(object({<br/>      type        = string<br/>      identifiers = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Permit terraform destroy to delete a non-empty bucket. Leave false in prod. | `bool` | `false` | no |
| <a name="input_ignore_public_acls"></a> [ignore\_public\_acls](#input\_ignore\_public\_acls) | Ignore public ACLs. | `bool` | `true` | no |
| <a name="input_intelligent_tiering"></a> [intelligent\_tiering](#input\_intelligent\_tiering) | Intelligent-Tiering archive configurations, keyed by configuration name. Each enables the Archive Access (90-730 days) and/or Deep Archive Access (180-730 days) tiers for objects in the INTELLIGENT\_TIERING storage class, optionally filtered by prefix / tags. Empty map = none. | <pre>map(object({<br/>    enabled                  = optional(bool, true)<br/>    prefix                   = optional(string)<br/>    tags                     = optional(map(string))<br/>    archive_access_days      = optional(number)<br/>    deep_archive_access_days = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN. Required when sse\_algorithm = aws:kms. | `string` | `null` | no |
| <a name="input_lifecycle_prefix"></a> [lifecycle\_prefix](#input\_lifecycle\_prefix) | Object prefix the lifecycle rule applies to. Empty string = whole bucket. | `string` | `""` | no |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Expire noncurrent versions after N days. Null = never. | `number` | `365` | no |
| <a name="input_noncurrent_version_transition_days"></a> [noncurrent\_version\_transition\_days](#input\_noncurrent\_version\_transition\_days) | Transition noncurrent versions to GLACIER after N days. Null = skip. | `number` | `30` | no |
| <a name="input_object_lock"></a> [object\_lock](#input\_object\_lock) | Default Object Lock retention (WORM). Set exactly one of days or years. Requires versioning\_enabled = true. Object Lock cannot be disabled once enabled. Null = no Object Lock. | <pre>object({<br/>    mode  = string<br/>    days  = optional(number)<br/>    years = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_replication"></a> [replication](#input\_replication) | Replicate every object to another bucket (same- or cross-region, same- or<br/>cross-account). The destination bucket must already exist with versioning<br/>enabled. role\_arn = null creates a role scoped to this bucket, the<br/>destination bucket, and the KMS keys involved. When the source bucket uses<br/>aws:kms, destination\_kms\_key\_arn is required. storage\_class = null keeps<br/>the source object's class. Requires versioning\_enabled = true. Null = no<br/>replication. | <pre>object({<br/>    destination_bucket_arn    = string<br/>    storage_class             = optional(string)<br/>    destination_kms_key_arn   = optional(string)<br/>    role_arn                  = optional(string)<br/>    delete_marker_replication = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_restrict_public_buckets"></a> [restrict\_public\_buckets](#input\_restrict\_public\_buckets) | Restrict public bucket policies. | `bool` | `true` | no |
| <a name="input_sse_algorithm"></a> [sse\_algorithm](#input\_sse\_algorithm) | Server-side encryption algorithm: AES256 or aws:kms. | `string` | `"AES256"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |
| <a name="input_transition_to_glacier_days"></a> [transition\_to\_glacier\_days](#input\_transition\_to\_glacier\_days) | Transition current objects to GLACIER after N days. Null = skip. | `number` | `90` | no |
| <a name="input_transition_to_ia_days"></a> [transition\_to\_ia\_days](#input\_transition\_to\_ia\_days) | Transition current objects to STANDARD\_IA after N days. Null = skip. | `number` | `30` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Enable object versioning. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | Bucket ARN. |
| <a name="output_bucket_domain_name"></a> [bucket\_domain\_name](#output\_bucket\_domain\_name) | Bucket domain name (used in legacy virtual-hosted-style URLs). |
| <a name="output_bucket_hosted_zone_id"></a> [bucket\_hosted\_zone\_id](#output\_bucket\_hosted\_zone\_id) | Route53 hosted zone ID for the bucket's region (handy when fronting with CloudFront). |
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | Bucket name (also the bucket ID). |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Regional bucket domain name. Prefer this over bucket\_domain\_name in modern AWS regions. |
| <a name="output_replication_role_arn"></a> [replication\_role\_arn](#output\_replication\_role\_arn) | IAM role S3 uses for replication — the module-created role, or replication.role\_arn when supplied. Null when replication is disabled. |
<!-- END_TF_DOCS -->
