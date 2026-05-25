# terraform-aws-blueprint

Production-grade Terraform modules for AWS infrastructure.

[![Terraform](https://img.shields.io/badge/terraform-%E2%89%A5%201.5-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/aws--provider-%E2%89%A5%205.0-FF9900?logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/your-org/terraform-aws-blueprint/actions/workflows/terraform-validate.yml/badge.svg)](https://github.com/your-org/terraform-aws-blueprint/actions/workflows/terraform-validate.yml)

A small, opinionated library of Terraform modules that codify the patterns a
platform team typically reaches for on day one in AWS: a multi-AZ VPC, an EKS
cluster with IRSA wired up, a hardened RDS, a curated set of IAM roles, and a
secure-by-default S3 bucket. Every module is independently consumable and
follows the same conventions (validated variables, consistent tagging, sensible
production defaults, no hidden state).

## Quick start

```hcl
module "vpc" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/vpc?ref=v1.0.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```

Run `terraform init && terraform apply` and you have a multi-AZ VPC with public
and private subnets, per-AZ NAT gateways, and VPC Flow Logs landing in an
encrypted S3 bucket with lifecycle tiering.

For end-to-end examples (`vpc` + `eks` + `rds` + `s3-secure` wired together),
see [`examples/full-stack`](examples/full-stack/).

## Modules

| Module | Description | Docs |
|--------|-------------|------|
| `vpc` | Multi-AZ VPC with public/private subnets, NAT (single or per-AZ), and optional VPC Flow Logs to S3. | [modules/vpc](modules/vpc/) |
| `eks` | EKS control plane + managed node group, OIDC provider for IRSA, KMS-encrypted secrets, full control-plane logging. | [modules/eks](modules/eks/) |
| `rds` | Multi-AZ RDS (Postgres / MySQL) with encrypted storage, Secrets-Manager-backed master credentials, Performance Insights, Enhanced Monitoring. | [modules/rds](modules/rds/) |
| `iam-roles` | Curated platform IAM roles: EKS cluster, EKS node, IRSA, cross-account CI deployer. | [modules/iam-roles](modules/iam-roles/) |
| `s3-secure` | S3 bucket with public access blocked, ACLs disabled, encryption + versioning + lifecycle + TLS-only policy. | [modules/s3-secure](modules/s3-secure/) |

## Examples

| Example | What it shows |
|---------|---------------|
| [`simple-vpc`](examples/simple-vpc/) | Minimal `vpc` call. Good starter / sanity check. |
| [`eks-cluster`](examples/eks-cluster/) | `vpc` + `eks` wired together: nodes in private subnets. |
| [`full-stack`](examples/full-stack/) | `vpc` + `eks` + `rds` + `s3-secure` + IRSA — the reference deployment. |

## Design principles

- **Least privilege by default.** No role gets `AdministratorAccess` from this
  library. IAM is module-scoped, AWS-managed policies are used only where AWS
  expects them, and IRSA is the canonical pattern for workload credentials.
  The CI deployer role takes allow-only statement lists from the caller — there
  are no wildcard escape hatches.
- **Encryption everywhere.** RDS storage is encrypted, EKS secrets are
  KMS-envelope-encrypted, S3 buckets ship with SSE on and a bucket policy
  denying plaintext (HTTP) traffic. KMS keys default to customer-managed where
  it matters, with key rotation enabled.
- **Multi-AZ defaults.** Subnets, NAT, RDS, and EKS node groups all spread
  across AZs unless the caller explicitly opts out for cost reasons. The `vpc`
  module exposes a `single | per_az` NAT switch so the trade-off is explicit.
- **Tagging is a contract.** Every resource gets `Name`, `Environment`,
  `ManagedBy=Terraform`, `Project`, and a `Module` tag, merged with any
  caller-supplied tags via a shared `locals.common_tags` map. This is the
  baseline cost-allocation and ownership story.
- **Naming is consistent.** Resources follow
  `${name_prefix}-${environment}-${resource_type}`. Names are stable enough to
  reference from outside Terraform (e.g. CloudWatch alarms) without being so
  rigid that two stacks in the same account collide.
- **Validated inputs.** Every variable has a type and description; CIDRs,
  enums, ranges, and identifier formats use `validation` blocks so bad input
  fails at plan time, not apply time.
- **Stateful resources are protected.** RDS ships with `deletion_protection`
  on, takes a final snapshot in prod, and keeps its Secrets Manager secret in
  the recovery window. S3 enables versioning. EKS node groups
  `ignore_changes` on desired capacity so Cluster Autoscaler / Karpenter can
  own runtime sizing without Terraform fighting back.
- **No hidden coupling.** Modules don't reach into each other. Wiring (e.g.
  RDS ingress from EKS nodes) happens in the root module using outputs — see
  the `full-stack` example.

## Requirements

| Tool / provider | Version |
|-----------------|---------|
| Terraform | `>= 1.5.0` |
| AWS provider | `>= 5.0` |
| Kubernetes provider (only for `eks` module's `aws-auth` management) | `>= 2.20` |
| TLS provider (only for `eks` module's OIDC thumbprint) | `>= 4.0` |
| Random provider (only for `rds` module) | `>= 3.5` |

Region and credentials are taken from your AWS provider config — no module
hardcodes a region or account ID.

## Repository layout

```
.
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   ├── iam-roles/
│   └── s3-secure/
├── examples/
│   ├── simple-vpc/
│   ├── eks-cluster/
│   └── full-stack/
├── .github/workflows/terraform-validate.yml
├── .pre-commit-config.yaml
├── .gitignore
├── LICENSE
└── README.md
```

## Local development

Install the [pre-commit](https://pre-commit.com/) hooks once:

```bash
pre-commit install
```

The hooks run `terraform fmt`, `terraform validate`, `terraform_docs`,
`tflint`, and `trivy` on every commit, along with the usual whitespace /
merge-conflict checks.

To run validation manually against the whole tree:

```bash
terraform fmt -check -recursive
for d in modules/* examples/*; do
  (cd "$d" && terraform init -backend=false && terraform validate)
done
```

CI runs the same checks on every PR ([`.github/workflows/terraform-validate.yml`](.github/workflows/terraform-validate.yml))
and posts a summary comment.

## Contributing

PRs welcome. Before opening one:

1. Run `pre-commit run --all-files` locally.
2. Update the relevant module README — the `inputs` and `outputs` tables are
   re-generated by `terraform_docs` but the prose and the usage block are
   hand-written.
3. If you change a module's interface, bump the example that uses it.
4. Keep changes scoped: one module per PR is ideal.

For larger changes (new modules, breaking changes to existing ones), open an
issue first to discuss the design.

## License

[MIT](LICENSE).
