# 0006 — S3-native state locking replaces DynamoDB

**Status:** Accepted (v0.4.0; default flips at v1.0.0)

## Context

The S3 backend historically needed a DynamoDB table for state locking.
Terraform 1.10 added `use_lockfile = true`, which locks with a conditional
write of a `.tflock` object next to the state file, and Terraform 1.11
deprecated the `dynamodb_table` argument.

## Decision

`state-backend` gains `enable_dynamodb_lock`. When `false`, no table is
created and `backend_config_hcl` emits `use_lockfile = true`. The default
stays `true` until 1.0 ([0004](0004-opt-in-then-flip.md)) so existing
backends are not asked to delete their lock table on upgrade.

## Consequences

- One fewer resource, IAM permission set, and bill line per backend.
- Consumers on Terraform < 1.10 cannot use the S3-native mode; they keep the
  default until they upgrade.
- Migrating a live backend is a two-step change (switch every working
  directory to `use_lockfile`, then drop the table). The table has deletion
  protection, so the module README documents the explicit steps rather than
  letting a plan destroy it.
