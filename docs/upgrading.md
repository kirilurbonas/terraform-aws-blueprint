# Upgrading

Every minor release in `0.x` is safe to adopt on default inputs: plans show no
destructive changes, and where a resource address moved, a `moved` block
migrates state for you. Safer behaviour that *would* change existing
infrastructure ships behind an opt-in flag first and becomes the default at
`v1.0.0` — see [ADR 0004](adr/0004-opt-in-then-flip.md).

This page lists those flags so you can adopt them on your own schedule.

## Flags that flip at `v1.0.0`

Set these now to get the `1.0` behaviour early. Each row says what the first
plan after switching will do.

| Module | Input | Today | At 1.0 | First plan after opting in |
|--------|-------|-------|--------|----------------------------|
| `rds` | `manage_master_password` | `false` | `true` | Destroys the module-managed `random_password` and Secrets Manager secret; RDS creates its own secret. **Update anything that reads `master_secret_arn` to read `master_user_secret_arn`.** |
| `state-backend` | `enable_dynamodb_lock` | `true` | `false` | Destroys the lock table. Deletion protection blocks this on purpose — follow the [migration steps](../modules/state-backend/README.md) instead. |
| `vpc` | `manage_default_security_group` | `false` | `true` | Removes every rule from the VPC's default security group. Check nothing is attached to it first (`aws ec2 describe-network-interfaces --filters Name=group-id,Values=<sg>`). |

## Inputs that need a change at the call site

Additive in `0.4.0`, but you will hit them on your first plan if your stack
has the pattern they fix:

- **`rds.allowed_security_groups`** — if you pass security-group IDs created
  in the same apply (`module.eks.node_security_group_id`), move them from
  `allowed_security_group_ids` (list) to `allowed_security_groups` (map with
  your own static keys). The list form cannot be planned with unknown IDs. The
  move replaces each ingress rule once. See
  [ADR 0007](adr/0007-static-keys-for-computed-ids.md).
- **`iam-roles.create_irsa_inline_policy`** — set to `true` when
  `irsa_inline_policy_json` is computed in the same apply (for example from an
  `aws_iam_policy_document` that references a bucket you are creating).

## State moves handled automatically

These addresses gained a `count` in `0.4.0`. The module ships `moved` blocks;
`terraform plan` reports the move and no resource is replaced.

| Module | From | To |
|--------|------|----|
| `eks` | `aws_iam_openid_connect_provider.this` | `aws_iam_openid_connect_provider.this[0]` |
| `rds` | `random_password.master`, `aws_secretsmanager_secret.master`, `aws_secretsmanager_secret_version.master` | `…[0]` |
| `state-backend` | `aws_dynamodb_table.lock` | `aws_dynamodb_table.lock[0]` |

## Provider and Terraform versions

| Library version | Terraform | AWS provider |
|-----------------|-----------|--------------|
| `0.3.x` – `0.5.x` | `>= 1.5.0` | `>= 6.0, < 7.0` |

`state-backend` with `enable_dynamodb_lock = false` emits `use_lockfile = true`,
which the *consuming* stacks need Terraform `>= 1.10` to use.
