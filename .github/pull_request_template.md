## Summary

<!-- 1–3 sentences on what this PR does and why. -->

## Scope

- [ ] Module(s) touched: <!-- vpc / eks / rds / iam-roles / s3-secure / kms / state-backend / example -->
- [ ] Breaking change? If yes, add `BREAKING:` line below and a `CHANGELOG.md` entry under the next release.

<!-- BREAKING: <one-line summary of the break and the migration path> -->

## Verification

- [ ] `terraform fmt -recursive` clean
- [ ] `terraform validate` clean for every changed module + example
- [ ] `terraform test` passes in every changed module
- [ ] CI is green

## Notes for reviewers

<!-- Anything non-obvious: why a particular choice, what was tried and rejected, follow-ups. -->
