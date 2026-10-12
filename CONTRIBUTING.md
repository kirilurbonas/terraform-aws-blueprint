# Contributing

Thanks for the interest. This repo is a library of opinionated production
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

You also need `terraform`, `tflint`, `terraform-docs`, and `trivy` on `PATH`
for the `Makefile` targets, plus `conftest` and Moto (`pipx install
'moto[server]'`) for `make policy`.

## Running checks

Everything goes through the [`Makefile`](Makefile), and CI calls the same
targets — so a green `make all` locally is a green pipeline:

```bash
make all             # fmt-check, validate, validate-floor, lint, test, docs-check, security, policy
```

Individual targets: `make help`.

Three of them are worth knowing about:

- **`make validate-floor`** re-validates every module with the `aws` provider
  pinned to the floor of its declared constraint. Without it, a module can
  start depending on a newer provider feature and nothing notices until a
  consumer pinned to the floor hits a plan-time error — which is exactly how
  `vpc` and `state-backend` came to require v6 while advertising `>= 5.40`.
- **`make policy`** plans every example against [Moto](https://github.com/getmoto/moto)
  (a local AWS API emulator — no account, no credentials) and evaluates the
  plan JSON with the Conftest rules in [`policy/`](policy/). Module tests
  check that each module builds what it says; policy checks that what the
  examples actually compose stays inside the library's security invariants.
  A new invariant needs a rule *and* a violating fixture in
  `policy/policy_test.rego`.
- **`make lint`** relies on the shared [`.tflint.hcl`](.tflint.hcl). Never pass
  `--only` on the command line: it narrows the rule set silently, and it is why
  the AWS ruleset went unenforced for two releases.

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

## PR labels

[`.github/release-drafter.yml`](.github/release-drafter.yml) turns labels into
release-note categories and resolves the next version, so label every PR:

| Label | Release-note section | Version bump |
|-------|---------------------|--------------|
| `feature`, `enhancement` | Added | minor |
| `change` | Changed | minor |
| `fix`, `bug` | Fixed | patch |
| `removal` | Removed | minor |
| `security` | Security | patch |
| `dependencies` | Dependencies | patch |
| `documentation` | Documentation | patch |
| `breaking` | — | **major** |
| `skip-changelog` | excluded | — |

Conventional-commit PR titles (`feat:`, `fix:`, `refactor:`) are auto-labelled;
`breaking` needs either a `!` in the title or `BREAKING:` in the body.

## Release process

1. Land changes on `main` via PR (CI green required), labelled per the table
   above.
2. Update `CHANGELOG.md` under the relevant section. The drafted release notes
   are a cross-check, not a replacement — `CHANGELOG.md` stays hand-written
   because it carries the migration guidance the drafter can't infer.
3. Bump the version and tag: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push --tags`.
4. Publish the draft release that
   [`release-drafter.yml`](.github/workflows/release-drafter.yml) has been
   maintaining on `main`.

Major version for breaking changes; minor for additive features; patch for
bug fixes. See [`ROADMAP.md`](ROADMAP.md) for how breaking changes are staged
behind opt-in flags before `v1.0.0` flips them.

## Reporting issues

If you find a bug, please include:

- Affected module + version (tag).
- Terraform + AWS provider versions.
- Minimal repro (`terraform plan` output is usually enough).

For security issues see [`SECURITY.md`](SECURITY.md) — do not file them
publicly.
