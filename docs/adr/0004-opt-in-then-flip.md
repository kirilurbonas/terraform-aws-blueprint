# 0004 — Secure-default changes ship opt-in, flip at a major version

**Status:** Accepted (v0.3.0)

## Context

Several improvements change what already-deployed infrastructure looks like:
RDS-managed master passwords instead of a Terraform-generated one, S3-native
state locking instead of a DynamoDB table, a rule-less default security group.
Switching any of these silently on a minor upgrade would produce plans that
destroy and recreate secrets, delete lock tables, or cut traffic — for every
consumer, at the same time, on a version bump they expected to be safe.

## Decision

A change that would alter existing state ships in two steps:

1. **Opt-in** in a minor release, as a variable whose default reproduces
   today's behaviour exactly. Tests assert the default plan is unchanged.
   Where the change moves a resource address (adding `count`), a `moved`
   block migrates state with no manual step.
2. **Flip** the default in the next major release, with an entry in
   [`docs/upgrading.md`](../upgrading.md) and the CHANGELOG.

New modules are exempt: they start with the secure default because there is
no existing state to protect.

## Consequences

- Upgrading within a major version never produces a destructive plan from
  defaults alone.
- Until the flip, the safest configuration is not the default one. The
  upgrade guide lists every opt-in flag that will flip so consumers can adopt
  them early.
- Variables accumulate until the major release removes the superseded paths.
