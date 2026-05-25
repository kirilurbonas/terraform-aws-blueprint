# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0 caveat: minor versions may contain breaking changes. Breaking changes
are explicitly called out under each release.

## [Unreleased]

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
