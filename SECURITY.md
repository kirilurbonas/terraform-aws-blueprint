# Security policy

## Supported versions

| Version | Supported |
|---------|-----------|
| `main`  | ✅ |
| Latest released `vX.Y` | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not file a public GitHub issue.** Use GitHub's private
vulnerability reporting:

1. Go to the repository's [Security tab](https://github.com/kirilurbonas/terraform-aws-blueprint/security).
2. Click "Report a vulnerability".
3. Describe the issue, affected modules, and reproduction steps.

I will acknowledge within 5 business days and aim to ship a fix or mitigation
guidance within 30 days, depending on severity.

## Scope

In scope:
- IAM policy/role gaps that grant more than the documented permissions.
- Resources created without intended encryption / public-access controls.
- Logic bugs that can lead to data loss or unintended deletion.
- Sensitive values leaking into outputs without `sensitive = true`.

Out of scope:
- AWS service vulnerabilities (report directly to AWS).
- Defaults that are intentionally documented as opt-in / cost-driven.
- Issues that require already having admin in the AWS account.
