# terraform-aws-blueprint

**Production-grade Terraform modules for AWS infrastructure.**

[![Terraform](https://img.shields.io/badge/terraform-%E2%89%A5%201.5-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/aws--provider-%E2%89%A5%205.40-FF9900?logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/kirilurbonas/terraform-aws-blueprint/actions/workflows/terraform-validate.yml/badge.svg)](https://github.com/kirilurbonas/terraform-aws-blueprint/actions/workflows/terraform-validate.yml)
[![Release](https://img.shields.io/github/v/release/kirilurbonas/terraform-aws-blueprint?display_name=tag&sort=semver)](https://github.com/kirilurbonas/terraform-aws-blueprint/releases)

An opinionated library of Terraform modules that codify the patterns a platform
team typically reaches for on day one in AWS: a multi-AZ VPC, an EKS cluster
with multiple node groups and IRSA wired up, a hardened RDS, a curated set of
IAM roles, a secure-by-default S3 bucket, a customer-managed KMS key, and the
S3 + DynamoDB pair that backs a remote `terraform { backend "s3" {} }`. Every
module is independently consumable and follows the same conventions: validated
inputs, consistent tagging, sensible production defaults, no hidden state.

## Architecture (full-stack example)

```
              ┌──────────────────────────────────────────────────────────────┐
              │                            VPC                                │
              │  3 AZs · per-AZ NAT · S3 gateway + ECR/STS/Logs endpoints     │
              │  Flow Logs → S3 (encrypted, lifecycle-tiered)                 │
              └─────┬───────────────────────┬──────────────────────┬──────────┘
                    │ private subnets        │                      │
                    ▼                         ▼                      ▼
         ┌──────────────────┐       ┌──────────────────┐    ┌──────────────┐
         │       EKS        │       │       RDS        │    │  S3 secure   │
         │  control plane   │       │  Postgres 16     │    │   bucket     │
         │  • system NG     │       │  Multi-AZ + RR   │◀───│  KMS·VVS·TLS │
         │    (ON_DEMAND)   │       │  Secrets Manager │    └─────┬────────┘
         │  • apps NG       │       └─────▲────────────┘          │
         │    (SPOT, mixed) │             │ SG-to-SG only         │
         │  • addons: CNI / │             │                       │
         │    coredns /     │             │                       │
         │    kube-proxy    │             │                       │
         │  • IMDSv2 req.   │             │                       │
         │  • Access Entries│             │                       │
         └────┬─────────────┘             │                       │
              │ OIDC                       │                       │
              ▼                            │                       │
         ┌──────────────────────────────────┴───────────────────────┴────┐
         │                  Customer-managed KMS key                     │
         │      (RDS storage · S3 SSE-KMS · Secrets Manager · …)         │
         └───────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────────────────────────────────────┐
              │   IAM roles: eks-cluster · eks-node · IRSA · ci-deployer     │
              │       IRSA: app/app SA → s3:* on artifacts bucket            │
              └──────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  state-backend (one-off bootstrap)                                      │
  │  S3 bucket (versioned, encrypted, TLS-only) + DynamoDB lock table       │
  │  → `terraform { backend "s3" {…} }` for every downstream stack          │
  └─────────────────────────────────────────────────────────────────────────┘
```

## Quick start

```hcl
module "vpc" {
  source = "github.com/kirilurbonas/terraform-aws-blueprint//modules/vpc?ref=v0.2.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

For end-to-end (`vpc` + `eks` + `rds` + `s3-secure` + `kms` + IRSA) see
[`examples/full-stack`](examples/full-stack/).

## Modules

| Module | Purpose |
|--------|---------|
| [`vpc`](modules/vpc/) | Multi-AZ VPC, public/private subnets, NAT (single or per-AZ), optional VPC Flow Logs to S3, S3 gateway + interface endpoints. |
| [`eks`](modules/eks/) | EKS control plane + **multiple managed node groups** (ON_DEMAND / SPOT, taints/labels per group), **launch-template-backed nodes with IMDSv2 required**, **managed add-ons** (CNI / coredns / kube-proxy / EBS CSI / …), OIDC provider for IRSA, **Access Entries** (no `aws-auth`), KMS envelope encryption, full control-plane logging. |
| [`rds`](modules/rds/) | Multi-AZ RDS (Postgres / MySQL), KMS-encrypted, Secrets-Manager-backed master credentials, Performance Insights, Enhanced Monitoring, deterministic final snapshot, **read replicas**. |
| [`iam-roles`](modules/iam-roles/) | Curated platform IAM roles: EKS cluster, EKS node, IRSA, cross-account CI deployer (allow-only statement lists). |
| [`s3-secure`](modules/s3-secure/) | S3 bucket with public access blocked, ACLs disabled, encryption + versioning + lifecycle + TLS-only policy + deny-unencrypted-uploads policy. |
| [`kms`](modules/kms/) | Customer-managed KMS key with annual rotation, alias, and an explicit key policy (administrators / users / service principals). |
| [`state-backend`](modules/state-backend/) | S3 bucket + DynamoDB lock table for a Terraform remote backend. Emits a ready-to-paste backend config block. |

## Examples

| Example | What it shows | Est. cost (us-east-1) |
|---------|---------------|-----------------------|
| [`simple-vpc`](examples/simple-vpc/) | Minimal `vpc` call. | ~$32/mo |
| [`eks-cluster`](examples/eks-cluster/) | `vpc` + `eks` wired together; private endpoint, default node group, managed add-ons, VPC endpoints. | ~$320/mo |
| [`full-stack`](examples/full-stack/) | `vpc` + `eks` + `rds` + `s3-secure` + `kms` + IRSA — two node groups, read replica, fully tagged. | ~$1060/mo |
| [`prod-overrides`](examples/prod-overrides/) | `override.tf` pattern for bolting `prevent_destroy = true` onto module-managed stateful resources. | ~$32/mo |

## Design principles

- **Least privilege by default.** No role gets `AdministratorAccess` from this
  library. IAM is module-scoped, AWS-managed policies are used only where AWS
  expects them, and IRSA is the canonical pattern for workload credentials.
  The CI deployer role takes allow-only statement lists from the caller — there
  are no wildcard escape hatches.
- **Encryption everywhere.** RDS storage, EKS secrets (KMS envelope), S3
  (SSE-S3 or SSE-KMS), EBS volumes on EKS nodes — all encrypted by default.
  S3 buckets ship with a bucket policy denying plaintext (HTTP) traffic and
  unencrypted uploads. The `kms` module makes it trivial to bring a
  customer-managed key with rotation and a curated key policy.
- **IMDSv2 required.** Every EKS node runs under a launch template that sets
  `http_tokens = "required"`. No more long-tail SSRF-to-credential-theft
  footguns.
- **Multi-AZ defaults.** Subnets, NAT, RDS, and EKS node groups all spread
  across AZs unless the caller explicitly opts out for cost reasons. The `vpc`
  module exposes a `single | per_az` NAT switch so the trade-off is explicit.
- **No legacy patterns.** EKS uses **Access Entries** (the IAM-API replacement
  for `aws-auth`, GA 2023) — no in-cluster bootstrap, no `kubernetes` provider
  required just to apply the module. Security groups use the v5
  `aws_vpc_security_group_*_rule` resources, not the deprecated
  `aws_security_group_rule`.
- **Tagging is a contract.** Every resource gets `Name`, `Environment`,
  `ManagedBy=Terraform`, `Project`, and a `Module` tag, merged with any
  caller-supplied tags via a shared `locals.common_tags` map. The pattern is
  identical across all seven modules.
- **Consistent naming.** Resources follow
  `${name_prefix}-${environment}-${resource}` unless an AWS naming constraint
  forces otherwise.
- **Validated inputs.** Every variable has a type and description; CIDRs,
  enums, ranges, and identifier formats use `validation` blocks so bad input
  fails at plan time, not apply time.
- **Stateful resources are protected.** RDS ships with `deletion_protection`
  on and takes a deterministic final snapshot in prod; the master secret is
  kept in a 30-day Secrets Manager recovery window. S3 enables versioning.
  EKS node groups `ignore_changes` on `desired_size` so Cluster Autoscaler /
  Karpenter can own runtime sizing without Terraform fighting back. For hard
  `lifecycle.prevent_destroy = true` see
  [`examples/prod-overrides`](examples/prod-overrides/).
- **No hidden coupling.** Modules don't reach into each other. Wiring (e.g.
  RDS ingress from EKS nodes) happens in the root module using outputs — see
  the `full-stack` example.

## Requirements

| Tool / provider | Version |
|-----------------|---------|
| Terraform | `>= 1.5.0` (`terraform test` + `optional()` defaults) |
| AWS provider | `>= 5.40` (Access Entries, v5 SG rule resources) |
| Random provider (only for `rds`) | `>= 3.5` |

Region and credentials come from your AWS provider config — no module
hardcodes a region or account ID.

## Repository layout

```
.
├── modules/
│   ├── vpc/                 # multi-AZ networking + VPC endpoints
│   ├── eks/                 # EKS w/ multi-NG, addons, access entries, IMDSv2
│   ├── rds/                 # Postgres/MySQL, Secrets Manager, read replicas
│   ├── iam-roles/           # cluster / node / IRSA / CI deployer
│   ├── s3-secure/           # secure-by-default bucket
│   ├── kms/                 # CMK with explicit policy
│   └── state-backend/       # S3 + DynamoDB for `terraform backend "s3"`
├── examples/
│   ├── simple-vpc/          # sandbox VPC
│   ├── eks-cluster/         # VPC + EKS
│   ├── full-stack/          # VPC + EKS + RDS + S3 + KMS + IRSA
│   └── prod-overrides/      # override.tf pattern for prevent_destroy
├── .github/
│   ├── workflows/terraform-validate.yml
│   ├── dependabot.yml
│   ├── CODEOWNERS
│   ├── pull_request_template.md
│   └── ISSUE_TEMPLATE/
├── .pre-commit-config.yaml
├── .terraform-docs.yml
├── .gitignore
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md
```

## Local development

Install the [pre-commit](https://pre-commit.com/) hooks once:

```bash
pre-commit install
```

The hooks run `terraform fmt`, `terraform validate`, `terraform_docs`,
`tflint`, and `trivy` on every commit.

Run module tests (plan-only, against `mock_provider`):

```bash
cd modules/<name>
terraform init -backend=false
terraform test
```

Run validation against the whole tree:

```bash
terraform fmt -check -recursive
for d in modules/* examples/*; do
  (cd "$d" && terraform init -backend=false && terraform validate)
done
```

CI runs all of the above plus `tfsec` (HIGH severity fails the build) on
every PR and posts a sticky summary comment:
[`.github/workflows/terraform-validate.yml`](.github/workflows/terraform-validate.yml).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). For security issues see
[`SECURITY.md`](SECURITY.md) — please don't file them publicly.

## License

[MIT](LICENSE).
