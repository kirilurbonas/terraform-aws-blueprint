# 0002 — Plan-only tests against `mock_provider`

**Status:** Accepted (v0.2.0)

## Context

The usual way to test Terraform modules end-to-end is Terratest: apply into a
real account, probe the result, destroy. For this library that means EKS
clusters (15+ minutes each way), Multi-AZ RDS (similar), NAT gateways, and the
credential management and cleanup automation needed to keep a CI account from
leaking resources and money. Failures are dominated by eventual consistency
and quota limits rather than module bugs.

Terraform 1.7 added `mock_provider` to `terraform test`, which lets a test
plan a module with every provider call stubbed out.

## Decision

Every module ships `tests/*.tftest.hcl` that run `command = plan` against
`mock_provider "aws"`. Tests assert on planned resource attributes, on counts
and keys of `for_each` fan-out, and — via `expect_failures` — that every
`validation` block and precondition rejects what it should.

Integration concerns that a module-level test cannot see are covered by two
other gates instead of apply tests:

- `make validate-floor` validates each module against the oldest AWS provider
  it claims to support.
- `make policy` plans every example (real module composition, real provider
  schema) and enforces security invariants on the plan JSON — see
  [0003](0003-policy-on-plan-json.md).

## Consequences

- The full suite runs in about a minute, needs no credentials, and costs
  nothing, so it runs on every PR.
- Plan-only tests cannot catch AWS API rejections that the provider schema
  does not model (e.g. an instance class unavailable in a region). These
  surface on first apply in a consumer's account.
- Tests assert behaviour the module controls; they do not re-test the AWS
  provider.
