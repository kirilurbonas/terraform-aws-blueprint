# ecr

Private ECR repositories with immutable tags, scan on push, KMS encryption and
a lifecycle policy on every repository, plus optional cross-account access and
optional registry-level settings (scanning, pull-through cache, replication).

## Features

- One repository per `repositories` map entry, keyed by repository name
- `IMMUTABLE` tags and scan on push by default, overridable per repository
- KMS encryption by default (`aws/ecr` AWS managed key, or `kms_key_arn` for a
  customer managed key); `AES256` available. Encryption settings are fixed at
  creation — changing them replaces every repository
- Lifecycle policy on every repository, built from module-level defaults with
  per-repository overrides:
  1. expire untagged images 14 days after push
  2. keep the last 30 images tagged `v*` / `release*`
  3. keep the last 100 images not matched by rules 1 and 2 (`tagStatus = any`,
     always the last rule)
- Repository policy only when a repository sets `pull_principals`,
  `push_principals` or `lambda_pull`:
  - `CrossAccountPull` — `BatchGetImage`, `GetDownloadUrlForLayer`,
    `BatchCheckLayerAvailability`
  - `CrossAccountPush` — the pull actions plus the layer-upload and
    `PutImage` actions
  - `LambdaPull` — `lambda.amazonaws.com`, scoped by `aws:sourceArn` to
    functions in this account and in the pull principals' accounts
  - `*` principals are rejected; bare account IDs are expanded to
    `arn:<partition>:iam::<id>:root`
- Optional, off by default, registry-level resources: registry scanning
  configuration, pull-through cache rules, same-account cross-Region
  replication

## Lifecycle policy

ECR evaluates rules in `rulePriority` order and an image matched by a rule's
tag selection cannot be expired by a later rule, so images tagged `v*` /
`release*` are only ever counted by rule 2, and rule 3 handles everything else
that is tagged (commit SHAs, branch names). Rule priorities are assigned from
list position, so the `any` rule always has the highest value, as ECR requires.

| Setting | Module default | Per-repository override | Disable |
|---------|----------------|-------------------------|---------|
| Untagged expiry (days) | `lifecycle_untagged_expire_days = 14` | `untagged_expire_days` | — |
| Tagged images kept | `lifecycle_keep_tagged_count = 30` | `keep_tagged_count` | — |
| Tag prefixes for rule 2 | `lifecycle_tagged_prefixes = ["v", "release"]` | `tagged_prefixes` | `[]` drops rule 2 |
| Other images kept | `lifecycle_keep_any_count = 100` | `keep_any_count` | module default `null` drops rule 3 |

## Registry-level resources

`registry_scanning`, `pull_through_cache_rules` and `replication_regions`
manage settings that exist once per registry (account + Region), not per
repository. Applying them overwrites whatever was configured before, and two
stacks that both set them overwrite each other on every apply. Set them in
exactly one stack per account and Region, and leave them at their defaults
(`null`, `{}`, `[]`) everywhere else.

- `registry_scanning` replaces repository-level `scan_on_push` once applied.
  `CONTINUOUS_SCAN` requires `scan_type = "ENHANCED"` (Amazon Inspector,
  billed separately)
- Pull-through cache rules for authenticated upstreams (Docker Hub, GitHub,
  GitLab, Quay) need `credential_arn` — a Secrets Manager secret whose name
  starts with `ecr-pullthroughcache/`
- `replication_regions` replicates every repository in the registry to the
  listed Regions in the same account. Replica repositories are created by ECR,
  not by this module, and use `AES256` unless a repository creation template
  says otherwise

## Usage

```hcl
module "ecr" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/ecr?ref=v0.4.0"

  environment = "prod"
  project     = "blueprint"
  kms_key_arn = module.kms.key_arn

  repositories = {
    "blueprint/api" = {
      pull_principals = ["444455556666"]
      push_principals = ["arn:aws:iam::111122223333:role/ci-deployer"]
    }
    "blueprint/worker" = {
      lambda_pull          = true
      untagged_expire_days = 3
    }
    "blueprint/scratch" = {
      image_tag_mutability = "MUTABLE"
      force_delete         = true
      tagged_prefixes      = []
    }
  }
}

# module.ecr.repository_urls["blueprint/api"]
```

### Registry settings (one stack per account and Region)

```hcl
module "ecr_registry" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/ecr?ref=v0.4.0"

  environment = "prod"
  project     = "blueprint"

  registry_scanning = {
    scan_type = "ENHANCED"
    rules = [
      { scan_frequency = "CONTINUOUS_SCAN", filter = "blueprint/*" },
      { scan_frequency = "SCAN_ON_PUSH" },
    ]
  }

  pull_through_cache_rules = {
    ecr-public = { upstream_registry_url = "public.ecr.aws" }
  }

  replication_regions = ["eu-west-1"]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `environment` | `string` | — | yes | `dev`/`staging`/`prod`. |
| `project` | `string` | — | yes | Project tag. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |
| `repositories` | `map(object)` | `{}` | no | Repositories keyed by name, with per-repository settings. |
| `encryption_type` | `string` | `"KMS"` | no | `KMS` or `AES256`. |
| `kms_key_arn` | `string` | `null` | no | Customer managed key; `null` = `aws/ecr`. |
| `lifecycle_untagged_expire_days` | `number` | `14` | no | Untagged image expiry. |
| `lifecycle_keep_tagged_count` | `number` | `30` | no | Prefixed tagged images kept. |
| `lifecycle_tagged_prefixes` | `list(string)` | `["v", "release"]` | no | Prefixes for the tagged rule. |
| `lifecycle_keep_any_count` | `number` | `100` | no | Other images kept; `null` drops the rule. |
| `registry_scanning` | `object` | `null` | no | Registry scanning configuration. |
| `pull_through_cache_rules` | `map(object)` | `{}` | no | Pull-through cache rules keyed by prefix. |
| `replication_regions` | `list(string)` | `[]` | no | Same-account replication Regions. |

## Outputs

| Name | Description |
|------|-------------|
| `repository_arns` | Map of name → repository ARN. |
| `repository_urls` | Map of name → repository URL. |
| `repository_registry_ids` | Map of name → registry ID. |
| `registry_id` | Caller's registry (account) ID. |

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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_pull_through_cache_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_pull_through_cache_rule) | resource |
| [aws_ecr_registry_scanning_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_registry_scanning_configuration) | resource |
| [aws_ecr_replication_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_replication_configuration) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.repository](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | n/a | yes |
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | Repository encryption: KMS or AES256. Applies to every repository and cannot be changed without replacing the repository. | `string` | `"KMS"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN used when encryption\_type = KMS. Null uses the AWS managed key (aws/ecr). | `string` | `null` | no |
| <a name="input_lifecycle_keep_any_count"></a> [lifecycle\_keep\_any\_count](#input\_lifecycle\_keep\_any\_count) | Default: number of images to keep among those not matched by the untagged or keep-tagged rules (e.g. commit-SHA tags). Evaluated last. Null omits that rule. | `number` | `100` | no |
| <a name="input_lifecycle_keep_tagged_count"></a> [lifecycle\_keep\_tagged\_count](#input\_lifecycle\_keep\_tagged\_count) | Default: number of images to keep whose tag starts with one of lifecycle\_tagged\_prefixes. | `number` | `30` | no |
| <a name="input_lifecycle_tagged_prefixes"></a> [lifecycle\_tagged\_prefixes](#input\_lifecycle\_tagged\_prefixes) | Default: tag prefixes counted by the keep-tagged rule. Empty list omits that rule. | `list(string)` | <pre>[<br/>  "v",<br/>  "release"<br/>]</pre> | no |
| <a name="input_lifecycle_untagged_expire_days"></a> [lifecycle\_untagged\_expire\_days](#input\_lifecycle\_untagged\_expire\_days) | Default: expire untagged images this many days after push. | `number` | `14` | no |
| <a name="input_pull_through_cache_rules"></a> [pull\_through\_cache\_rules](#input\_pull\_through\_cache\_rules) | Pull-through cache rules, keyed by the ECR repository prefix (e.g. ecr-public, docker-hub). credential\_arn is a Secrets Manager secret whose name starts with ecr-pullthroughcache/, required by authenticated upstreams. Registry-level: manage from one stack per account and Region. | <pre>map(object({<br/>    upstream_registry_url = string<br/>    credential_arn        = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_registry_scanning"></a> [registry\_scanning](#input\_registry\_scanning) | Registry scanning configuration (BASIC or ENHANCED). Registry-wide singleton: overrides repository scan\_on\_push settings and any configuration made elsewhere. Manage it from one stack per account and Region. Null = leave untouched. | <pre>object({<br/>    scan_type = string<br/>    rules = optional(list(object({<br/>      scan_frequency = string<br/>      filter         = optional(string, "*")<br/>    })), [])<br/>  })</pre> | `null` | no |
| <a name="input_replication_regions"></a> [replication\_regions](#input\_replication\_regions) | Regions to replicate every repository in this registry to, within the same account. Registry-wide singleton: replaces any existing replication configuration. Must not include the current Region. Empty list = leave untouched. | `list(string)` | `[]` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | ECR repositories, keyed by repository name. Lifecycle fields left null use<br/>the module-level lifecycle\_* defaults. pull\_principals / push\_principals<br/>are 12-digit AWS account IDs or IAM ARNs (root, role or user) granted<br/>cross-account pull / push through a repository policy; lambda\_pull = true<br/>lets Lambda functions in this account and in the pull\_principals' accounts<br/>pull images. A repository policy is created only when one of those three is<br/>set. | <pre>map(object({<br/>    image_tag_mutability = optional(string, "IMMUTABLE")<br/>    scan_on_push         = optional(bool, true)<br/>    force_delete         = optional(bool, false)<br/>    keep_tagged_count    = optional(number)<br/>    tagged_prefixes      = optional(list(string))<br/>    untagged_expire_days = optional(number)<br/>    keep_any_count       = optional(number)<br/>    pull_principals      = optional(list(string), [])<br/>    push_principals      = optional(list(string), [])<br/>    lambda_pull          = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every repository. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_registry_id"></a> [registry\_id](#output\_registry\_id) | Registry ID (account ID) of the caller's private registry. |
| <a name="output_repository_arns"></a> [repository\_arns](#output\_repository\_arns) | Map of repository name to repository ARN. |
| <a name="output_repository_registry_ids"></a> [repository\_registry\_ids](#output\_repository\_registry\_ids) | Map of repository name to the registry ID (account ID) that owns it. |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository name to repository URL (ACCOUNT.dkr.ecr.REGION.amazonaws.com/NAME). |
<!-- END_TF_DOCS -->
