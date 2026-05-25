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
