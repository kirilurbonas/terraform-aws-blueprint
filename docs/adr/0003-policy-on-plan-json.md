# 0003 — Policy-as-code on plan JSON, planned against Moto

**Status:** Accepted (v0.4.0)

## Context

Module tests prove each module in isolation. They do not prove that what a
consumer *composes* stays secure: an example could wire a security group
ingress from `0.0.0.0/0` on port 22, or a new module could ship a log group
without retention, and every per-module assertion would still pass.

Static scanners (Trivy) read HCL. They cannot resolve variables passed between
modules, `for_each` fan-out, or conditionals — which is why Trivy reports
some findings it cannot evaluate and misses others.

Plan JSON (`terraform show -json`) has everything resolved, but producing a
plan needs the AWS provider to authenticate and to answer a few data sources
(`aws_availability_zones`, `aws_caller_identity`).

## Decision

`policy/` holds Rego rules evaluated by Conftest against the plan JSON of
every example. `scripts/policy-check.sh` produces those plans by pointing the
AWS provider at a local [Moto](https://github.com/getmoto/moto) server through
`AWS_ENDPOINT_URL`. Plans run with `-refresh=false`; nothing is created.

Rules cover network exposure, encryption at rest, IMDSv2, ALB hardening, IAM
escalation paths and web-identity trust scoping, and the tagging contract.
Every rule has a violating fixture in `policy/policy_test.rego`
(`conftest verify`), so a rule that silently stops matching fails CI.

## Consequences

- The examples are now executable proof of the library's claims, not just
  documentation — and planning them for real already caught one bug
  (`for_each` over computed security-group IDs in `rds`, see
  [0007](0007-static-keys-for-computed-ids.md)) that `terraform validate`
  never could.
- Values unknown until apply (most ARNs, some policy JSON) cannot be checked
  on a plan. Rules skip them explicitly rather than guess; module tests
  cover their construction.
- CI gains a Python dependency (Moto), pinned in the workflow.
