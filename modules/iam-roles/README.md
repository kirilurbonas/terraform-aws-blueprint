# iam-roles

Curated catalogue of the IAM roles a platform team usually needs around an EKS
cluster. Each role is opt-in via a `create_*` flag, so this module can be
instantiated multiple times in the same root module for different consumers.

## Roles provided

- **`eks_cluster_role`** — trust policy for `eks.amazonaws.com`,
  `AmazonEKSClusterPolicy` attached.
- **`eks_node_role`** — trust policy for `ec2.amazonaws.com` with
  `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and
  `AmazonEC2ContainerRegistryReadOnly` attached.
- **`irsa_role`** — trust policy federated through a cluster's OIDC provider,
  scoped to a single `namespace/serviceaccount`. Attach AWS-managed and/or
  inline policies for the workload's actual permissions.
- **`ci_deployer_role`** — cross-account assumable role for CI/CD. Caller
  supplies trusted principal ARNs, an optional `sts:ExternalId`, optional
  source-IP allow-list, and the allow-only IAM statements the deployer needs.

## Usage

```hcl
module "platform_roles" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/iam-roles?ref=v1.0.0"

  name_prefix = "platform"
  project     = "blueprint"

  create_irsa_role           = true
  irsa_oidc_provider_arn     = module.eks.oidc_provider_arn
  irsa_oidc_provider_url     = module.eks.cluster_oidc_issuer_url
  irsa_namespace             = "kube-system"
  irsa_service_account_name  = "external-dns"
  irsa_managed_policy_arns   = []
  irsa_inline_policy_json    = data.aws_iam_policy_document.external_dns.json

  create_ci_deployer_role  = true
  ci_trusted_principal_arns = ["arn:aws:iam::111122223333:role/github-oidc"]
  ci_external_id            = "blueprint-prod"
  ci_allowed_statements = [
    {
      sid       = "TerraformState"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["arn:aws:s3:::tfstate-blueprint/*"]
    },
  ]
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix on every role name. |
| `project` | `string` | — | yes | Project tag. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |
| `create_eks_cluster_role` | `bool` | `false` | no | Create the EKS control-plane role. |
| `create_eks_node_role` | `bool` | `false` | no | Create the EKS node-group role. |
| `create_irsa_role` | `bool` | `false` | no | Create an IRSA role. |
| `irsa_oidc_provider_arn` | `string` | `null` | when IRSA | OIDC provider ARN. |
| `irsa_oidc_provider_url` | `string` | `null` | when IRSA | OIDC issuer URL. |
| `irsa_namespace` | `string` | `"default"` | no | K8s namespace. |
| `irsa_service_account_name` | `string` | `null` | when IRSA | K8s service account. |
| `irsa_managed_policy_arns` | `list(string)` | `[]` | no | Managed policies. |
| `irsa_inline_policy_json` | `string` | `null` | no | Inline policy JSON. |
| `create_ci_deployer_role` | `bool` | `false` | no | Create the CI deployer role. |
| `ci_trusted_principal_arns` | `list(string)` | `[]` | when CI | Principals allowed to assume. |
| `ci_external_id` | `string` | `null` | no | Required ExternalId. |
| `ci_source_ip_cidrs` | `list(string)` | `[]` | no | Source-IP allow-list. |
| `ci_max_session_duration` | `number` | `3600` | no | Max session seconds. |
| `ci_allowed_statements` | `list(object)` | `[]` | when CI | Allow-only IAM statements. |

## Outputs

| Name | Description |
|------|-------------|
| `eks_cluster_role_arn` / `_name` | EKS cluster role. |
| `eks_node_role_arn` / `_name` | EKS node role. |
| `irsa_role_arn` / `_name` | IRSA role. |
| `ci_deployer_role_arn` / `_name` | CI deployer role. |

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs auto-generates the full requirements / providers / resources / inputs / outputs tables here when the pre-commit hook runs. The hand-written inputs/outputs tables above stay; this block is appended below them. -->
<!-- END_TF_DOCS -->
