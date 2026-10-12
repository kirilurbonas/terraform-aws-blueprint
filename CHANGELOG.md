# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 caveat: minor versions may contain breaking changes. Breaking changes
are explicitly called out under each release.

## [Unreleased]

## [0.4.0] - 2026-10-12

Module hardening, and a policy gate that plans every example for real. Every
change is additive: on default inputs the plan for an existing stack is
unchanged, and where a resource gained a `count`, a `moved` block migrates
state automatically. Defaults that will change at `v1.0.0` are listed in
[`docs/upgrading.md`](docs/upgrading.md).

### Fixed

- **`examples/full-stack` could not be planned.** `rds` created its
  security-group ingress with `for_each = toset(var.allowed_security_group_ids)`,
  and the example passed `module.eks.node_security_group_id` — unknown until
  apply — so `terraform plan` failed with *Invalid for_each argument*.
  `terraform validate` cannot see this, so it shipped in every release. `rds`
  now takes `allowed_security_groups`, a map with caller-chosen static keys,
  and the example uses it ([ADR 0007](docs/adr/0007-static-keys-for-computed-ids.md)).
- **Same class of bug in `iam-roles`:** the IRSA inline policy's `count`
  depended on whether a computed JSON string was null. New
  `create_irsa_inline_policy` makes the decision plan-time-known.

### Added

#### Policy-as-code

- **`policy/`** — Conftest rules evaluated on the plan JSON of every example:
  no SSH/RDP from the internet, S3 public-access blocks and encryption per
  bucket, ACLs disabled, RDS/Aurora encrypted and private, encrypted EBS,
  IMDSv2-only launch templates, EKS secrets encryption and no world-open API
  endpoint, ALB invalid-header dropping / HTTPS-only / TLS 1.3, KMS rotation,
  log retention, no admin-policy attachments, no `Action: "*"`, no open or
  unscoped web-identity trust, and the required tag set. Each rule has a
  violating fixture in `policy/policy_test.rego`.
- **`scripts/policy-check.sh` / `make policy`** plans each example against
  Moto (a local AWS API emulator) — no account or credentials — and runs
  Conftest on the result. New `policy` CI job and PR-summary row
  ([ADR 0003](docs/adr/0003-policy-on-plan-json.md)).

#### `rds`

- `manage_master_password` — RDS-native `manage_master_user_password`, so the
  master password never enters Terraform state. Optional
  `master_user_secret_kms_key_id` (falls back to `kms_key_arn`). New output
  `master_user_secret_arn`; `master_password` / `master_secret_arn` are `null`
  in this mode. **Default flips at 1.0.**
- `allowed_security_groups` (map, label → SG ID) for ingress from security
  groups created in the same apply.
- `ca_cert_identifier`, `copy_tags_to_snapshot`,
  `iam_database_authentication_enabled`, `apply_immediately` (null keeps the
  existing non-prod-applies-immediately rule), `blue_green_update`.
- Optional CloudWatch alarms (CPU, free storage, freeable memory, connections)
  behind `create_cloudwatch_alarms`, with `cloudwatch_alarm_thresholds` and
  SNS `alarm_actions` / `ok_actions`. New output `cloudwatch_alarm_arns`.

#### `eks`

- **EKS Pod Identity** — `pod_identity_associations` creates
  `aws_eks_pod_identity_association`s; new `pod_identity_associations` output.
  `eks-pod-identity-agent` is documented in the add-on set
  ([ADR 0005](docs/adr/0005-workload-identity.md)).
- `create_oidc_provider` (default `true`) to drop the IRSA OIDC provider on
  Pod-Identity-only clusters; `oidc_provider_arn` is `null` when off.
- `upgrade_policy` (`STANDARD` / `EXTENDED`) and `zonal_shift_config`.
- `cluster_addons` validation: `service_account_role_arn` must be an IAM role
  ARN, `configuration_values` a JSON/YAML object, `resolve_conflicts_*` values
  the EKS API accepts.

#### `vpc`

- `manage_default_security_group` strips every rule from the VPC's default
  security group (CIS EC2.2). **Default flips at 1.0.**
- **Database subnet tier** — `enable_database_subnets`, per-AZ route tables
  with no internet route (`database_subnets_nat_access` optional), an
  `aws_db_subnet_group`, and `database_*` outputs.
- **Configurable subnet sizing** — `subnet_newbits` and explicit
  `public_/private_/database_subnet_cidrs`. The default carve is unchanged and
  capacity limits are now checked at plan time.
- `flow_logs_kms_key_arn` — SSE-KMS with S3 Bucket Keys on the module-managed
  flow-log bucket. The Trivy AWS-0132 suppression is removed.
- CloudWatch Logs as a flow-log destination
  (`flow_logs_destination_type = "cloud-watch-logs"`), with a log group and a
  delivery role whose trust is scoped by source account and ARN.
- VPC endpoint policies (`interface_endpoint_options[*].policy`,
  `s3_gateway_endpoint_policy`) and per-endpoint `private_dns_enabled`.

#### `iam-roles`

- `permissions_boundary_arn`, applied to every role the module creates.
- **GitHub Actions OIDC trust** for the CI deployer (`github_oidc`): `aud`
  pinned to `sts.amazonaws.com`, `sub` limited to listed repositories and
  branches / tags / environments / pull requests. Works alongside or instead
  of the cross-account principal + external ID path. Validation rejects
  configurations that would trust any owner or carry no selector.
- `create_github_oidc_provider` to create the account's
  `token.actions.githubusercontent.com` provider.
- Optional `environment`, applied as the `Environment` tag. The module was the
  only one that could not satisfy the tagging contract the README promises;
  the new tagging policy caught it.

#### `kms`

- `replica_regions` — an `aws_kms_replica_key` and alias per region, using the
  AWS provider v6 resource-level `region` (no provider aliases for callers to
  wire). Requires `multi_region = true`. New output `replica_key_arns`.
- `rotation_period_in_days` (90–2560); unset keeps the AWS default of 365.

#### `s3-secure`

- `object_lock` — GOVERNANCE / COMPLIANCE default retention. Enabled through
  `aws_s3_bucket_object_lock_configuration`, so existing buckets are not
  replaced; requires versioning.
- `replication` to an existing bucket (same- or cross-region), with a
  least-privilege role unless `role_arn` is given; SSE-KMS objects included
  automatically. New output `replication_role_arn`.
- `enable_eventbridge_notifications` and `intelligent_tiering`
  (Archive 90–730 days, Deep Archive 180–730 days).

#### `state-backend`

- `enable_dynamodb_lock` (default `true`). When `false`, no table is created
  and `backend_config_hcl` emits `use_lockfile = true` (S3-native locking,
  Terraform ≥ 1.10). **Default flips at 1.0**
  ([ADR 0006](docs/adr/0006-s3-native-state-locking.md)).
- `access_logging` and `replication` for state DR. Replication never copies
  delete markers. New output `replication_role_arn`.

#### Docs

- [`docs/adr/`](docs/adr/) — architecture decision records for the choices
  that shape the library.
- [`docs/upgrading.md`](docs/upgrading.md) — opt-in flags, the 1.0 default
  flips, and state moves.

### Changed

- `examples/full-stack` now uses the database subnet tier, an RDS-managed
  master password, a rule-less default security group, the Pod Identity agent
  add-on, and the `STANDARD` EKS upgrade policy.
- `state-backend.lock_table_name` is optional; it is required only when
  `enable_dynamodb_lock = true`.
- Resource addresses that gained a `count` (`eks` OIDC provider, `rds` master
  password and secret, `state-backend` lock table) migrate via `moved` blocks
  with no action needed.

## [0.3.0] - 2026-08-23

Two things at once: the module work that had been sitting unreleased, and a
foundation pass that fixes the tooling which was supposed to be enforcing this
library's quality bar. Along the way the foundation work exposed a provider
constraint that was never true.

### Fixed

- **The `aws >= 5.40` provider floor was wrong.** `vpc` and `state-backend`
  read `data.aws_region.current.region`, an attribute the AWS provider only
  exposes from v6.0 onward, so those two modules failed at `terraform validate`
  for anyone pinned below v6 — despite every module advertising `>= 5.40`. The
  constraint is now `>= 6.0, < 7.0` across the library, and CI validates every
  module against the declared floor so this cannot recur.
- **tflint's AWS ruleset never ran.** There was no `.tflint.hcl` anywhere in
  the tree, so `tflint --init` installed no plugins. Worse, `tflint --recursive`
  re-reads config from each working directory, so a root config alone is not
  enough — `TFLINT_CONFIG_FILE` must point at an absolute path or every
  subdirectory silently falls back to the bundled terraform ruleset. Both are
  fixed, and CI now asserts the AWS ruleset actually loaded before linting.
- **The `prod-overrides` example was incomplete in the repository.** The
  blanket `override.tf` rule in `.gitignore` excluded
  `examples/prod-overrides/override.tf` — the single file that example exists
  to demonstrate — so anyone cloning the repo got a README linking to a file
  that was not there. The example also gained the `outputs.tf` that
  `terraform_standard_module_structure` expects.
- **Security findings never reached GitHub code scanning.** The workflow
  requested `security-events: write` but nothing uploaded SARIF.

### Added

- **VPC flow-log hardening** — the `vpc` module now hardens its module-managed
  flow-log bucket with `BucketOwnerEnforced`, a TLS-only bucket policy, and the
  AWS log-delivery permissions Flow Logs need to actually write objects. It
  also exposes `flow_logs_file_format`,
  `flow_logs_hive_compatible_partitions`, and
  `flow_logs_per_hour_partition` for parquet- and analytics-friendly delivery.
- **RDS log-group management** — the `rds` module now creates CloudWatch log
  groups for exported database logs (primary + replicas) with configurable
  retention and optional KMS encryption via
  `cloudwatch_log_retention_days` / `cloudwatch_log_kms_key_arn`.
- **`ROADMAP.md`** — milestones through `v1.0.0`, which breaking changes are
  staged behind opt-in flags, and what has been explicitly ruled out.
- **`Makefile`** — `fmt`, `validate`, `validate-floor`, `lint`, `test`,
  `docs-check`, `security`, `all`. CI calls the same targets, so local checks
  and CI cannot drift.
- **`.tflint.hcl`** — shared rule set (terraform ruleset at `preset = "all"`
  plus the AWS ruleset) used by both CI and pre-commit.
- **Provider-floor CI job** — re-validates every module with `aws` pinned to
  the floor of its declared constraint.
- **Release automation** — `.github/workflows/release-drafter.yml` and
  `.github/release-drafter.yml`. `CONTRIBUTING.md` had documented a
  release-drafter workflow since 0.2.0; it now exists, and the PR labels it
  keys off are documented.
- **terraform-docs drift job** — CI fails when regenerating docs would change a
  file.
- **Committed lock files for the examples**, with hashes for `linux_amd64`,
  `linux_arm64`, `darwin_amd64`, and `darwin_arm64`. Examples are root modules,
  so pinning them makes example CI reproducible; the modules themselves stay
  unpinned by design. Dependabot now watches them.
- **CI hygiene** — concurrency cancellation, `workflow_dispatch`, and a
  `pre-commit` job covering the repo-hygiene hooks.

### Changed

- **EKS shared-node-role policy attachment** — `AmazonSSMManagedInstanceCore`
  is now attached once to the shared node IAM role even when multiple node
  groups enable SSM access, avoiding duplicate attachment churn.
- **Stronger module validation** — `eks`, `rds`, and `s3-secure` now validate
  more production-sensitive invariants such as node-group scaling bounds,
  access-entry namespace scoping, storage autoscaling bounds, exact-one bucket
  naming inputs, and KMS requirements for strict S3 encryption.
- **S3 strict upload enforcement** — the `s3-secure` module now denies uploads
  that use the wrong SSE algorithm and, in KMS mode, the wrong key ID.
- **tfsec replaced by Trivy.** tfsec is archived upstream and folded into
  Trivy, yet CI ran tfsec while pre-commit ran Trivy. One scanner now, in both
  places: every severity is reported to GitHub code scanning, and HIGH/CRITICAL
  gate the build. The switch surfaced three findings, recorded with written
  justifications in `.trivyignore.yaml` — unrestricted EKS egress and
  `map_public_ip_on_launch` on public subnets are deliberate and suppressed
  permanently; the flow-log bucket's lack of a customer-managed-key option is a
  real gap, so its suppression expires and is tracked for v0.4.0.
- **terraform-docs markers normalized** to `<!-- BEGIN_TF_DOCS -->` across
  modules and examples. Module READMEs previously carried a dead, empty
  `BEGIN_TF_DOCS` placeholder alongside the real block written by pre-commit
  under different markers. The generated tables now also include Modules, and
  empty sections are omitted.
- **Examples now `terraform init -lockfile=readonly`** in CI, so a stale
  committed lock file fails the build instead of being silently rewritten.
- `modules/state-backend`: the `aws_region` data source moved from `outputs.tf`
  to `main.tf`, matching every other module. No behaviour change.

### Upgrading from 0.2.x

No variable or output changes. The only thing that can block an upgrade is the
provider constraint: if you pin `aws ~> 5.x`, move to `~> 6.0`. Modules other
than `vpc` and `state-backend` did work on 5.40 and now require 6.0 as well —
the library carries a single floor so that the requirement is stated once and
tested once.

## [0.2.1] - 2026-05-25

### Fixed

- Drop unused `data "aws_caller_identity" "current"` from the `full-stack`
  example. It was unreferenced and tripped `tflint`'s
  `terraform_unused_declarations` rule, turning the v0.2.0 CI run red even
  though `validate` / `test` / `tfsec` were all green.

## [0.2.0] - 2026-05-25

### Added

- **New module `kms`** — customer-managed KMS key with annual rotation, alias,
  and an explicit key policy (administrators / users / service principals).
- **New module `state-backend`** — bootstraps an S3 bucket + DynamoDB lock
  table for downstream `terraform { backend "s3" {} }` consumers; emits a
  ready-to-paste backend config block.
- **EKS managed add-ons** — `cluster_addons` variable fans into
  `aws_eks_addon` (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, ...).
- **EKS multiple node groups** — `node_groups` map variable supports any
  number of differentiated groups (e.g. system / apps / gpu, mixed
  ON_DEMAND + SPOT, per-group taints/labels).
- **EKS launch templates** — every node group now runs under a module-managed
  launch template that enforces **IMDSv2 required**, encrypts the root EBS
  volume, and applies tag specifications to instances and volumes.
- **EKS Access Entries** — replaces the legacy `aws-auth` ConfigMap.
  `authentication_mode = "API"` by default; `access_entries` variable maps
  IAM principals to Kubernetes RBAC via the IAM API.
- **VPC endpoints** — `enable_s3_gateway_endpoint` (default true) and
  `interface_endpoints` (list) for ECR / STS / Logs / EC2 / etc., reducing
  NAT egress.
- **RDS read replicas** — `read_replicas` map variable creates per-replica
  `aws_db_instance` resources that inherit storage, SG, and parameter group
  from the primary.
- **`terraform test`** — every module ships with `tests/basic.tftest.hcl`
  exercising defaults, key combinations, and variable validation under
  `mock_provider`. CI runs these on every PR.
- **`examples/prod-overrides`** — documents the `override.tf` pattern for
  bolting `lifecycle.prevent_destroy = true` onto module-managed stateful
  resources.
- **Repo tooling** — `.terraform-docs.yml` (inject mode w/ BEGIN/END markers),
  `.github/dependabot.yml` (github-actions + terraform weekly), `CODEOWNERS`,
  `CONTRIBUTING.md`, `SECURITY.md`, PR template, bug/feature issue templates.
- **CI** — adds a `terraform test` matrix job, a `tfsec` job (HIGH severity
  fails the build), and switches to sticky PR comments via
  `marocchino/sticky-pull-request-comment` so re-runs edit one comment.
- **Architecture diagram** in root README; cost callouts in example READMEs.

### Changed

- **EKS provider requirement bumped to `aws >= 5.40`** — required for Access
  Entries (`aws_eks_access_entry`, `aws_eks_access_policy_association`).
- **OIDC thumbprint** is now a pinned literal (Amazon Root CA 1) exposed via
  the `oidc_thumbprint_list` variable, eliminating the `tls` provider
  dependency and the fragile plan-time HTTPS dial it required.
- **Security-group rules** migrated from the deprecated `aws_security_group_rule`
  to `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule`
  in the `vpc`, `eks`, and `rds` modules. Rules are now individually taggable.
- **RDS `final_snapshot_identifier`** is now a deterministic value
  (`${identifier}-final`) instead of `${identifier}-final-${timestamp()}`, which
  eliminated the perpetual plan diff on prod stacks.
- **Full-stack example** now uses two node groups (system ON_DEMAND with a
  CriticalAddonsOnly taint; apps SPOT with instance-family diversification),
  the new managed add-ons, a shared KMS key (for RDS + S3), one read replica,
  and VPC endpoints.

### Removed

- **EKS `aws-auth` ConfigMap management** (`manage_aws_auth`, `aws_auth_role_map`,
  `aws_auth_user_map` variables) — replaced by Access Entries. The
  `kubernetes` provider is no longer a dependency of this module.
- **`tls` provider dependency** from the EKS module.
- **EKS top-level node-group inputs** (`capacity_type`, `instance_types`,
  `ami_type`, `node_disk_size_gb`, `desired_capacity`, `min_capacity`,
  `max_capacity`, `node_labels`, `node_taints`, `enable_ssm_access`) — folded
  into the per-entry shape of the new `node_groups` map variable.

### Migration from 0.1.x

For the EKS module:

```diff
 module "eks" {
   source = "github.com/your-org/terraform-aws-blueprint//modules/eks?ref=v0.2.0"
   # ...
-  capacity_type    = "ON_DEMAND"
-  instance_types   = ["t3.large"]
-  desired_capacity = 2
-  min_capacity     = 1
-  max_capacity     = 4
-  manage_aws_auth  = true
-  aws_auth_role_map = [...]
+  node_groups = {
+    default = {
+      capacity_type  = "ON_DEMAND"
+      instance_types = ["t3.large"]
+      desired_size   = 2
+      min_size       = 1
+      max_size       = 4
+    }
+  }
+  access_entries = {
+    admin = {
+      principal_arn = "arn:aws:iam::123456789012:role/platform-admin"
+      policy_associations = [{
+        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
+        access_scope = { type = "cluster" }
+      }]
+    }
+  }
 }
```

State-wise: existing clusters that adopt 0.2.0 will see node-group resource
addresses change (from `aws_eks_node_group.this[0]` to
`aws_eks_node_group.this["default"]`). Use `moved` blocks or
`terraform state mv` to migrate without recreating nodes.

## [0.1.0] - 2026-05-25

### Added

- Initial public release.
- Modules: `vpc`, `eks`, `rds`, `iam-roles`, `s3-secure`.
- Examples: `simple-vpc`, `eks-cluster`, `full-stack`.
- CI: `terraform fmt`, matrix `terraform init + validate`, `tflint`, PR
  comment summary.
- Pre-commit: fmt / validate / docs / tflint / trivy.
- MIT license.
