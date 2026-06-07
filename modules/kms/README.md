# kms

Customer-managed KMS key with annual rotation, alias, and an explicit key
policy you can hand to administrators, IAM users, and AWS service principals.

## Features

- Symmetric KMS key, key rotation enabled
- Configurable deletion window (default 30 days)
- Multi-region option for cross-region replication scenarios
- Key policy template that:
  - Grants the AWS account root full access (required to keep the key
    recoverable — never remove this)
  - Adds an opt-in `KeyAdministration` statement for admin ARNs
  - Adds an opt-in `KeyUsage` statement for caller IAM ARNs
  - Adds an opt-in `AllowServiceUse` statement for AWS service principals
    (e.g. `s3.amazonaws.com`, `logs.amazonaws.com`)
- Alias resource (`alias/<your-name>`)

## Usage

```hcl
module "app_kms" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/kms?ref=v0.2.0"

  environment = "prod"
  project     = "blueprint"
  alias       = "blueprint-prod-app"
  description = "App-level encryption key (S3, Secrets)"

  key_administrators = ["arn:aws:iam::111122223333:role/platform-admin"]
  key_users          = ["arn:aws:iam::111122223333:role/blueprint-prod-eks-node-*"]
  service_principals = ["logs.us-east-1.amazonaws.com"]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `alias` | `string` | — | yes | Alias name (no `alias/` prefix). |
| `description` | `string` | `"Customer-managed encryption key"` | no | Key description. |
| `deletion_window_in_days` | `number` | `30` | no | 7–30. |
| `multi_region` | `bool` | `false` | no | Create as multi-region primary. |
| `key_administrators` | `list(string)` | `[]` | no | Admin IAM ARNs. |
| `key_users` | `list(string)` | `[]` | no | User IAM ARNs (encrypt/decrypt). |
| `service_principals` | `list(string)` | `[]` | no | AWS service principals. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |

## Outputs

| Name | Description |
|------|-------------|
| `key_id` | KMS key ID. |
| `key_arn` | KMS key ARN. |
| `alias_arn` | Alias ARN. |
| `alias_name` | Full alias including `alias/`. |

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
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alias"></a> [alias](#input\_alias) | Alias for the key (without the `alias/` prefix). | `string` | n/a | yes |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Pending-deletion window. AWS minimum is 7, max 30. | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Free-text description on the KMS key. | `string` | `"Customer-managed encryption key"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_key_administrators"></a> [key\_administrators](#input\_key\_administrators) | IAM ARNs allowed to administer (rotate / disable / tag) the key. Root is always allowed. | `list(string)` | `[]` | no |
| <a name="input_key_users"></a> [key\_users](#input\_key\_users) | IAM ARNs allowed cryptographic operations (Encrypt / Decrypt / GenerateDataKey). | `list(string)` | `[]` | no |
| <a name="input_multi_region"></a> [multi\_region](#input\_multi\_region) | Create a multi-region primary key. Cross-region replicas must be added in the consuming regions. | `bool` | `false` | no |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to the key. | `string` | n/a | yes |
| <a name="input_service_principals"></a> [service\_principals](#input\_service\_principals) | AWS service principals (e.g. s3.amazonaws.com) granted cryptographic operations via the key policy. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto the key. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the key alias. |
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | Full alias including the `alias/` prefix. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | KMS key ARN. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | KMS key ID. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
