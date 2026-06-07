# example: prod-overrides

Demonstrates the `override.tf` pattern for bolting `prevent_destroy = true`
onto module-managed stateful resources without forking the module source.

## Why this exists

Terraform's `lifecycle.prevent_destroy` must be a literal — it cannot be
parameterized off a variable like `environment`. Modules in this library
therefore default to `deletion_protection = true` (RDS) / versioning + lifecycle
(S3), but cannot themselves toggle `prevent_destroy`.

The canonical workaround: put an `override.tf` file next to your module
call. Terraform merges override files on top of the resources defined in the
called modules.

## Layout

- [`main.tf`](main.tf) — VPC + RDS + S3 wired up.
- [`override.tf`](override.tf) — commented templates showing how to add
  `prevent_destroy` to RDS and S3 resources.

## Usage

```bash
cd examples/prod-overrides
terraform init
# Uncomment the resources you want protected in override.tf, then:
terraform plan
```

## Notes

- `prevent_destroy` is a guard, not a permission system. Combine it with
  `deletion_protection`, IAM, and a tested backup strategy.
- For Terraform ≥ 1.5 you can also use `removed` / `import` blocks for more
  surgical state manipulation, but `prevent_destroy` itself still needs the
  override pattern.
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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bucket"></a> [bucket](#module\_bucket) | ../../modules/s3-secure | n/a |
| <a name="module_rds"></a> [rds](#module\_rds) | ../../modules/rds | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../../modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | `"us-east-1"` | no |

## Outputs

No outputs.
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
