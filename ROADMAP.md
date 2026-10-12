# Roadmap

Where this library is going, and what "done" looks like at each stop. Items are
grouped by the release that carries them. Anything not listed here has not been
agreed — open an issue first (see [`CONTRIBUTING.md`](CONTRIBUTING.md)).

## Versioning policy

Pre-1.0, minor versions may contain breaking changes; each one is called out
explicitly in [`CHANGELOG.md`](CHANGELOG.md).

**Breaking changes land in two steps.** A behaviour change that would break
existing state ships first as an opt-in variable defaulting to today's
behaviour. The default flips at `v1.0.0`, with a migration guide and `moved`
blocks. This means you can adopt the safer path on your own schedule instead of
on ours.

`v1.0.0` means: the variable and output contract is frozen, the secure defaults
are on, and breaking changes require a major bump.

## Status

| Milestone | Theme | State |
|-----------|-------|-------|
| `v0.1.0` | Initial five modules | Released |
| `v0.2.0` | KMS + state-backend, EKS access entries, multi-NG, tests | Released |
| `v0.2.1` | tflint fix in the full-stack example | Released |
| `v0.3.0` | Foundation: linting, scanning, release + docs enforcement | Released |
| **`v0.4.0`** | **Module hardening + policy-as-code** | **Ready to tag** |
| `v0.5.0` | Surface expansion | Planned |
| `v1.0.0` | Contract freeze | Planned |

---

## `v0.3.0` — Foundation

The quality bar this repo advertises was not actually being enforced. This
release makes the tooling real, and ships the module work that had been sitting
unreleased since 0.2.1.

- [x] **`.tflint.hcl` at the repo root**, enabling the terraform ruleset at
      `preset = "all"` plus the AWS ruleset. There was no tflint config anywhere
      in the tree, so `tflint --init` installed no plugins and the AWS ruleset
      never ran — in CI or locally. The pre-commit hook dropped its duplicated
      `--only` list, so both paths now lint identically.
- [x] **Absolute `TFLINT_CONFIG_FILE` everywhere tflint runs.** A root config
      alone is not sufficient: `tflint --recursive` re-reads config from each
      working directory, so every subdirectory silently falls back to the
      bundled terraform ruleset. CI now asserts `ruleset.aws` loaded before it
      lints, so this failure mode cannot return quietly.
- [x] **Retire tfsec, consolidate on Trivy.** tfsec is archived upstream and
      folded into Trivy, yet CI ran tfsec while pre-commit ran Trivy.
- [x] **Upload SARIF to GitHub code scanning.** The workflow already requested
      `security-events: write` but nothing ever used it. All severities are
      reported there; only HIGH/CRITICAL gate the build.
- [x] **`.trivyignore.yaml` with written justifications.** Switching scanners
      surfaced three findings. Two are deliberate design (unrestricted egress
      on EKS security groups; `map_public_ip_on_launch` on public subnets) and
      are suppressed permanently with the reasoning written down. The third —
      the flow-log bucket not accepting a CMK — is a real gap, so its
      suppression carries an expiry and a v0.4.0 roadmap item rather than being
      waved through.
- [x] **Fix the `prod-overrides` example.** `.gitignore`'s blanket `override.tf`
      rule excluded `examples/prod-overrides/override.tf` — the one file that
      example exists to demonstrate.
- [x] **Commit example lock files**, with hashes for the four platforms CI and
      developers actually use. Modules stay unpinned (correct for a reusable
      module); examples are root modules and pin. CI inits them with
      `-lockfile=readonly` so a stale lock file fails rather than being
      rewritten.
- [x] **Release automation.** `CONTRIBUTING.md` had documented a release-drafter
      workflow since 0.2.0 that did not exist. It exists now, with
      label-driven categories mirroring the Keep a Changelog sections.
- [x] **Enforce docs freshness in CI.** Module READMEs carried a dead, empty
      `BEGIN_TF_DOCS` placeholder alongside the real block that pre-commit wrote
      under different markers. Markers are normalized, and a `docs` job fails
      when regeneration would change a file.
- [x] **Correct the provider constraint.** This one was found by the new
      floor-validation job, not predicted: `vpc` and `state-backend` read
      `data.aws_region.current.region`, which the AWS provider only exposes from
      v6.0, so they never worked on the `>= 5.40` floor every module advertised.
      Now `>= 6.0, < 7.0` library-wide, with CI validating against the declared
      floor as well as the latest allowed version.
- [x] **`Makefile`.** `make fmt validate validate-floor lint test docs-check
      security` — CI calls the same targets, so local checks and CI cannot
      drift.
- [x] **CI hygiene.** Concurrency cancellation, `workflow_dispatch`, a
      `pre-commit` job, and Dependabot entries for the examples.

## `v0.4.0` — Module hardening

Every item is additive and opt-in. Defaults do not change until `v1.0.0`.

### `rds`

- [x] **`manage_master_password`** → RDS-native `manage_master_user_password`
      with `master_user_secret_kms_key_id`. Today the module generates the
      password with `random_password` and writes it to a module-managed Secrets
      Manager secret, which puts the plaintext password in Terraform state. The
      native path never does. New output `master_user_secret_arn`;
      `master_password` returns `null` in managed mode. **Default flips at 1.0.**
- [x] `ca_cert_identifier`, `copy_tags_to_snapshot`,
      `iam_database_authentication_enabled`, `apply_immediately`,
      `blue_green_update`.
- [x] Optional CloudWatch alarms (CPU, free storage, connection count) behind
      `create_cloudwatch_alarms`.

### `eks`

- [x] **EKS Pod Identity** — `pod_identity_associations` →
      `aws_eks_pod_identity_association`, plus `eks-pod-identity-agent` in the
      documented add-on set. The module supports only IRSA today; Pod Identity is
      the current AWS-recommended pattern and does not require an OIDC provider
      per cluster.
- [x] `create_oidc_provider` toggle, so IRSA can be switched off entirely when
      running Pod Identity.
- [x] Add-on passthrough for `service_account_role_arn` and
      `configuration_values`.
- [x] `upgrade_policy` (STANDARD / EXTENDED) and `zonal_shift_config`.

### `vpc`

- [x] **Lock down the default security group.** `aws_default_security_group` with
      no rules. Currently the VPC's default SG is left at AWS's default
      allow-all-from-self — a standard CIS finding.
- [x] **Database subnet tier** (`enable_database_subnets`) plus an
      `aws_db_subnet_group` output, so RDS stops sharing application private
      subnets.
- [x] **Configurable subnet sizing.** The CIDR carve is hardcoded to
      `cidrsubnet(vpc_cidr, 4, i)` / `i + 8`, which silently caps at 8 AZs and
      forces /20s. Replace with `subnet_newbits` plus explicit
      `public_subnet_cidrs` / `private_subnet_cidrs` overrides.
- [x] **`flow_logs_kms_key_arn`** — the module-managed flow-log bucket encrypts
      with SSE-S3 and accepts no customer-managed key. Trivy flags this
      (`AWS-0132`); the suppression in `.trivyignore.yaml` carries an expiry of
      2027-02-01 so the finding returns if this slips.
- [x] CloudWatch Logs as an alternative flow-log destination (S3 only today).
- [x] VPC endpoint policies and a `private_dns_enabled` toggle.

### `iam-roles`

- [x] **`permissions_boundary_arn`** on every created role. There is no boundary
      support at all today, which makes these roles unusable in accounts that
      mandate one.
- [x] **GitHub Actions OIDC trust** for the CI deployer role
      (`token.actions.githubusercontent.com` with `sub` conditions on repo,
      branch, and environment), alongside the existing cross-account principal +
      external ID path.

### `s3-secure`

- [x] Object Lock (governance / compliance mode), replication configuration,
      EventBridge notification toggle, intelligent-tiering.

### `kms`

- [x] `aws_kms_replica_key` when `multi_region = true`. The variable exists and
      sets the flag on the primary key, but there is no replica resource or
      output, so multi-region keys are only half-built.
- [x] Configurable `rotation_period_in_days`.

### `state-backend`

- [x] **`enable_dynamodb_lock` toggle.** Terraform 1.11 deprecates the S3
      backend's `dynamodb_table` argument in favour of S3-native locking. When
      the toggle is off, the emitted `backend_config_hcl` uses
      `use_lockfile = true` and no table is created. **Default flips at 1.0.**
- [x] Optional access logging and replication for state DR.

### Testing

- [x] Extend every `tests/basic.tftest.hcl` with positive assertions for the new
      flags and negative `expect_failures` for their validations.
- [x] **Policy-as-code.** A `policy/` directory of Conftest/OPA rules evaluated
      against `terraform show -json` plan output for each example, wired as a CI
      job. This catches security regressions that plan-only assertions miss —
      e.g. "no security group may allow 0.0.0.0/0 on port 22" as a repo-wide
      invariant rather than a per-module assertion. Plans run against Moto, so
      no AWS account is involved. Planning the examples for real immediately
      surfaced an `rds` `for_each` over computed security-group IDs that made
      `examples/full-stack` unplannable — fixed in the same release.

---

## `v0.5.0` — Surface expansion

Three modules, chosen because the existing set cannot serve a working
application without them:

- [ ] **`alb`** — application load balancer, the ingress path for the EKS and
      ECS workloads the library already provisions compute for.
- [ ] **`aurora`** — `aws_rds_cluster`, as a sibling to `rds` rather than a set
      of conditionals bolted into it.
- [ ] **`ecr`** — repositories with lifecycle policies, scan-on-push, and KMS.

Each ships with `tests/basic.tftest.hcl`, a README with terraform-docs markers,
a Dependabot entry, and a worked example.

---

## `v1.0.0` — Contract freeze

- [ ] Flip the opt-in defaults from `v0.4.0` (`rds.manage_master_password`,
      `state-backend.enable_dynamodb_lock`,
      `vpc.manage_default_security_group`) — tracked in
      [`docs/upgrading.md`](docs/upgrading.md).
- [ ] Remove the deprecated variables they replace.
- [ ] Migration guide in [`docs/upgrading.md`](docs/upgrading.md), with
      `moved` blocks where addresses change.
- [ ] Documented support policy for the frozen variable and output contract.

---

## Out of scope

Decided against, recorded so it does not get relitigated:

- **Terraform Registry publication.** Consumption stays
  `github.com/kirilurbonas/terraform-aws-blueprint//modules/<name>?ref=vX.Y.Z`.
  The registry's one-module-per-repo model fits this library poorly.
- **Real-AWS apply tests.** Tests stay plan-only against `mock_provider`. The
  cost, credential management, and flake surface of applying EKS clusters in CI
  buys less than deeper static analysis does.
- **Multi-cloud.** This is an AWS library.

## Deferred

Wanted, but not scheduled — the cost/benefit is not there yet:

- **IPv6 / dual-stack VPC.** Large surface change across subnets, routes, SGs,
  and endpoints; no consumer demand yet.
- **Karpenter wiring** (node role access entry, SQS interruption queue). Waiting
  until the `eks` module's Pod Identity work lands, since Karpenter's IAM story
  builds on it.
- **Fargate profiles.** Narrow audience relative to the maintenance cost.
- **RDS Proxy.** Belongs with the `aurora` work, not before it.
