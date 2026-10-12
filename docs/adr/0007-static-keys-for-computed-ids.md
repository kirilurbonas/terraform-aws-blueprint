# 0007 — `for_each` keys must be known at plan time

**Status:** Accepted (v0.4.0)

## Context

`for_each = toset(var.allowed_security_group_ids)` works when the caller
passes literal IDs. When the IDs come from a resource created in the same
apply — the normal case when composing `eks` and `rds` in one stack — they
are unknown at plan time and Terraform refuses to plan:

```
Error: Invalid for_each argument
The "for_each" set includes values derived from resource attributes that
cannot be determined until apply
```

`terraform validate` does not catch this; only a real plan does. The
`full-stack` example carried this bug from the initial release, unnoticed
until the policy job ([0003](0003-policy-on-plan-json.md)) started planning
it. The same hazard
applies to `count = var.x != null ? 1 : 0` when `var.x` is computed.

## Decision

- Any input that may carry values computed in the same apply and drives
  `for_each` is a **map with caller-chosen static keys**
  (`allowed_security_groups = { eks_nodes = module.eks.node_security_group_id }`).
  Lists remain for values that are literals in practice (CIDR blocks).
- Any optional input that drives `count` and may be computed gets an explicit
  boolean companion (`create_irsa_inline_policy = true`) so the decision does
  not depend on an unknown value.
- Existing list inputs stay for backwards compatibility; their descriptions
  state that IDs must be known at plan time.

## Consequences

- A slightly more verbose call site in exchange for stacks that plan on the
  first run.
- Resource addresses are keyed by meaningful labels (`from_sg_map["eks_nodes"]`)
  rather than opaque IDs, so swapping a security group is an in-place update
  instead of a destroy/create of the rule.
