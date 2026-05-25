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
