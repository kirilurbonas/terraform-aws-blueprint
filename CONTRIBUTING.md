# Contributing

Thanks for the interest. This repo is a portfolio of opinionated production
Terraform modules; the bar for changes is "would a platform team actually want
this in their library."

## Ground rules

- **One module per PR** when adding features. Bug fixes can span if they share
  a root cause.
- **Backwards-compatible by default.** Breaking variable / output changes need
  a `BREAKING:` line in the PR body, an entry in `CHANGELOG.md`, and a major
  version bump on the next release.
- **No expansion of scope without an issue first.** New modules, new optional
  AWS services, new third-party providers — open an issue and let's agree on
  the shape before any code lands.

## Local setup

```bash
pre-commit install
```

The hooks run `terraform fmt`, `terraform validate`, `terraform_docs`,
`tflint`, and `trivy` on every commit.

## Running tests

Every module has plan-only tests under `tests/`. They use `mock_provider` so
no AWS calls are made.

```bash
cd modules/<name>
terraform init -backend=false
terraform test
```

CI runs the same against every module on every PR.

## Style

- Variables: always declare `type` and `description`. Add `validation` for
  CIDRs, enums, ranges, and identifier formats.
- Outputs: always declare `description`. Mark `sensitive = true` where it
  belongs.
- Tags: use the `locals.common_tags` pattern — never tag a resource in isolation.
- Naming: `${name_prefix}-${environment}-${resource}` unless an AWS naming
  constraint forces otherwise.
- No hardcoded regions or account IDs. Always derive via data sources or
  variables.

## Commit messages

Imperative mood, short subject (≤ 70 chars), body explains *why* if non-obvious:

```
eks: switch managed node groups to launch templates

Required for IMDSv2 enforcement and per-volume tagging — the inline
node-group spec doesn't expose either.
```

## Release process

1. Land changes on `main` via PR (CI green required).
2. Update `CHANGELOG.md` under the relevant section.
3. Bump the version and tag: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push --tags`.
4. The release-drafter workflow turns the PR labels into release notes.

Major version for breaking changes; minor for additive features; patch for
bug fixes.

## Reporting issues

If you find a bug, please include:

- Affected module + version (tag).
- Terraform + AWS provider versions.
- Minimal repro (`terraform plan` output is usually enough).

For security issues see [`SECURITY.md`](SECURITY.md) — do not file them
publicly.
