# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 caveat: minor versions may contain breaking changes. Breaking changes
are explicitly called out under each release.

## [Unreleased]

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
