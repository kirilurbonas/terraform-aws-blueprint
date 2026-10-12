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
- **`ci_deployer_role`** — assumable role for CI/CD with two trust paths that
  can be used together: cross-account principal ARNs with an optional
  `sts:ExternalId`, and GitHub Actions OIDC federation scoped to specific
  repositories and branches / tags / environments / pull requests. Optional
  source-IP allow-list, and the allow-only IAM statements the deployer needs.

Every role accepts an optional permissions boundary
(`permissions_boundary_arn`), for accounts whose SCPs require one on all
IAM roles.

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
  create_irsa_inline_policy  = true # JSON is computed in the same apply

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

### IRSA inline policy computed in the same apply

Set `create_irsa_inline_policy = true` whenever `irsa_inline_policy_json` is
only known after apply — typically an `aws_iam_policy_document` that references
a bucket, table or key created in the same run. Without the flag Terraform
cannot decide at plan time whether to create the inline policy and fails with
`Invalid count argument`. Setting the flag without supplying the JSON is
rejected.

### GitHub Actions OIDC

`github_oidc` trusts the GitHub Actions OIDC issuer for the CI deployer role.
`aud` is pinned to `sts.amazonaws.com` and `sub` is matched (`StringLike`)
against one pattern per repository and selector:

| Selector | `sub` pattern |
|----------|---------------|
| `branches = ["main"]` | `repo:acme/infra:ref:refs/heads/main` |
| `tags = ["v*"]` | `repo:acme/infra:ref:refs/tags/v*` |
| `environments = ["prod"]` | `repo:acme/infra:environment:prod` |
| `pull_requests = true` | `repo:acme/infra:pull_request` |

At least one selector is required, and the repository owner must be literal
(`*/infra` and `*` are rejected), so the role can never trust every repository
on GitHub. Jobs that declare an `environment:` present the `environment:` form
of `sub`, not the branch form — list the environment, not the branch, for
those jobs.

An account holds one OIDC provider per issuer URL. Pass an existing one as
`github_oidc.provider_arn`, or set `create_github_oidc_provider = true` in
exactly one stack per account.

```hcl
module "ci_roles" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/iam-roles?ref=v0.4.0"

  name_prefix              = "platform"
  project                  = "blueprint"
  permissions_boundary_arn = "arn:aws:iam::111122223333:policy/platform-boundary"

  create_ci_deployer_role     = true
  create_github_oidc_provider = true
  github_oidc = {
    repositories = ["acme/infra"]
    branches     = ["main"]
    environments = ["prod"]
  }

  ci_allowed_statements = [
    {
      sid       = "TerraformState"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["arn:aws:s3:::tfstate-blueprint/*"]
    },
  ]
}
```

The workflow then needs `permissions: id-token: write` and
`aws-actions/configure-aws-credentials` with
`role-to-assume: <ci_deployer_role_arn>`.

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix on every role name. |
| `project` | `string` | — | yes | Project tag. |
| `environment` | `string` | `null` | no | Environment tag (dev, staging, prod). Set it when the roles belong to one environment. |
| `tags` | `map(string)` | `{}` | no | Extra tags. |
| `permissions_boundary_arn` | `string` | `null` | no | Permissions boundary on every role. |
| `create_eks_cluster_role` | `bool` | `false` | no | Create the EKS control-plane role. |
| `create_eks_node_role` | `bool` | `false` | no | Create the EKS node-group role. |
| `create_irsa_role` | `bool` | `false` | no | Create an IRSA role. |
| `irsa_oidc_provider_arn` | `string` | `null` | when IRSA | OIDC provider ARN. |
| `irsa_oidc_provider_url` | `string` | `null` | when IRSA | OIDC issuer URL. |
| `irsa_namespace` | `string` | `"default"` | no | K8s namespace. |
| `irsa_service_account_name` | `string` | `null` | when IRSA | K8s service account. |
| `irsa_managed_policy_arns` | `list(string)` | `[]` | no | Managed policies. |
| `irsa_inline_policy_json` | `string` | `null` | no | Inline policy JSON. |
| `create_irsa_inline_policy` | `bool` | `false` | when JSON is computed | Attach the inline policy even if its JSON is unknown at plan. |
| `create_ci_deployer_role` | `bool` | `false` | no | Create the CI deployer role. |
| `ci_trusted_principal_arns` | `list(string)` | `[]` | when CI | Principals allowed to assume. |
| `ci_external_id` | `string` | `null` | no | Required ExternalId. |
| `ci_source_ip_cidrs` | `list(string)` | `[]` | no | Source-IP allow-list. |
| `ci_max_session_duration` | `number` | `3600` | no | Max session seconds. |
| `ci_allowed_statements` | `list(object)` | `[]` | when CI | Allow-only IAM statements. |
| `github_oidc` | `object` | `null` | no | GitHub Actions OIDC trust for the CI role. |
| `create_github_oidc_provider` | `bool` | `false` | no | Create the GitHub Actions OIDC provider. |

## Outputs

| Name | Description |
|------|-------------|
| `eks_cluster_role_arn` / `_name` | EKS cluster role. |
| `eks_node_role_arn` / `_name` | EKS node role. |
| `irsa_role_arn` / `_name` | IRSA role. |
| `ci_deployer_role_arn` / `_name` | CI deployer role. |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0, < 7.0 |



## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.ci_deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.eks_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.eks_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ci_deployer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.irsa_inline](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.eks_cluster_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks_node_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks_node_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks_node_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.irsa_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.ci_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ci_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.eks_cluster_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.eks_node_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.irsa_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to every role name. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to all roles. | `string` | n/a | yes |
| <a name="input_ci_allowed_statements"></a> [ci\_allowed\_statements](#input\_ci\_allowed\_statements) | Allow-only IAM statements granted to the deployer role. Keep tightly scoped. | <pre>list(object({<br/>    sid       = optional(string)<br/>    actions   = list(string)<br/>    resources = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_ci_external_id"></a> [ci\_external\_id](#input\_ci\_external\_id) | Optional sts:ExternalId required when assuming the deployer role. | `string` | `null` | no |
| <a name="input_ci_max_session_duration"></a> [ci\_max\_session\_duration](#input\_ci\_max\_session\_duration) | Maximum session duration (seconds) for the deployer role. Range 3600 - 43200. | `number` | `3600` | no |
| <a name="input_ci_source_ip_cidrs"></a> [ci\_source\_ip\_cidrs](#input\_ci\_source\_ip\_cidrs) | Optional aws:SourceIp allow-list applied to every trust statement of the deployer role (cross-account and GitHub OIDC). | `list(string)` | `[]` | no |
| <a name="input_ci_trusted_principal_arns"></a> [ci\_trusted\_principal\_arns](#input\_ci\_trusted\_principal\_arns) | ARNs of IAM principals (typically a CI-account role or GitHub OIDC role) allowed to assume the deployer role. | `list(string)` | `[]` | no |
| <a name="input_create_ci_deployer_role"></a> [create\_ci\_deployer\_role](#input\_create\_ci\_deployer\_role) | Whether to create a cross-account CI/CD deployer role. | `bool` | `false` | no |
| <a name="input_create_eks_cluster_role"></a> [create\_eks\_cluster\_role](#input\_create\_eks\_cluster\_role) | Whether to create the EKS control-plane service role. | `bool` | `false` | no |
| <a name="input_create_eks_node_role"></a> [create\_eks\_node\_role](#input\_create\_eks\_node\_role) | Whether to create the EKS node-group instance role. | `bool` | `false` | no |
| <a name="input_create_github_oidc_provider"></a> [create\_github\_oidc\_provider](#input\_create\_github\_oidc\_provider) | Create the account's IAM OIDC provider for https://token.actions.githubusercontent.com. Only one can exist per account; leave false and pass github\_oidc.provider\_arn if it already exists. Requires create\_ci\_deployer\_role and github\_oidc. | `bool` | `false` | no |
| <a name="input_create_irsa_inline_policy"></a> [create\_irsa\_inline\_policy](#input\_create\_irsa\_inline\_policy) | Attach irsa\_inline\_policy\_json even when its value is unknown at plan time. Required when the policy JSON is computed in the same apply; without it Terraform cannot determine whether to create the policy. | `bool` | `false` | no |
| <a name="input_create_irsa_role"></a> [create\_irsa\_role](#input\_create\_irsa\_role) | Whether to create an IRSA role. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod), applied as the Environment tag. Optional because IAM roles are often account-wide rather than per-environment; set it whenever the roles belong to one environment so they satisfy the library's tagging contract. | `string` | `null` | no |
| <a name="input_github_oidc"></a> [github\_oidc](#input\_github\_oidc) | GitHub Actions OIDC trust for the CI deployer role. Null disables it.<br/>`repositories` are "owner/repo" (the repo part may use `*` wildcards; the<br/>owner may not). Each repository is trusted only for the listed `branches`,<br/>`tags`, `environments`, and/or pull\_request events — at least one selector<br/>is required. Set `provider_arn` to an existing<br/>token.actions.githubusercontent.com OIDC provider, or set<br/>create\_github\_oidc\_provider = true instead. | <pre>object({<br/>    repositories  = list(string)<br/>    branches      = optional(list(string), [])<br/>    environments  = optional(list(string), [])<br/>    tags          = optional(list(string), [])<br/>    pull_requests = optional(bool, false)<br/>    provider_arn  = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_irsa_inline_policy_json"></a> [irsa\_inline\_policy\_json](#input\_irsa\_inline\_policy\_json) | Optional inline IAM policy JSON attached to the IRSA role. If the JSON is only known after apply (computed in the same run), also set create\_irsa\_inline\_policy = true. | `string` | `null` | no |
| <a name="input_irsa_managed_policy_arns"></a> [irsa\_managed\_policy\_arns](#input\_irsa\_managed\_policy\_arns) | AWS-managed policies to attach to the IRSA role. | `list(string)` | `[]` | no |
| <a name="input_irsa_namespace"></a> [irsa\_namespace](#input\_irsa\_namespace) | Kubernetes namespace of the service account that may assume this role. | `string` | `"default"` | no |
| <a name="input_irsa_oidc_provider_arn"></a> [irsa\_oidc\_provider\_arn](#input\_irsa\_oidc\_provider\_arn) | ARN of the IAM OIDC provider that backs IRSA for the target EKS cluster. | `string` | `null` | no |
| <a name="input_irsa_oidc_provider_url"></a> [irsa\_oidc\_provider\_url](#input\_irsa\_oidc\_provider\_url) | OIDC issuer URL for the target EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE). | `string` | `null` | no |
| <a name="input_irsa_service_account_name"></a> [irsa\_service\_account\_name](#input\_irsa\_service\_account\_name) | Kubernetes service account name that may assume this role. | `string` | `null` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of an IAM managed policy set as the permissions boundary on every role this module creates. Null means no boundary. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged onto every role. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ci_deployer_role_arn"></a> [ci\_deployer\_role\_arn](#output\_ci\_deployer\_role\_arn) | ARN of the CI deployer role, or null if not created. |
| <a name="output_ci_deployer_role_name"></a> [ci\_deployer\_role\_name](#output\_ci\_deployer\_role\_name) | Name of the CI deployer role, or null if not created. |
| <a name="output_eks_cluster_role_arn"></a> [eks\_cluster\_role\_arn](#output\_eks\_cluster\_role\_arn) | ARN of the EKS control-plane role, or null if not created. |
| <a name="output_eks_cluster_role_name"></a> [eks\_cluster\_role\_name](#output\_eks\_cluster\_role\_name) | Name of the EKS control-plane role, or null if not created. |
| <a name="output_eks_node_role_arn"></a> [eks\_node\_role\_arn](#output\_eks\_node\_role\_arn) | ARN of the EKS node-group role, or null if not created. |
| <a name="output_eks_node_role_name"></a> [eks\_node\_role\_name](#output\_eks\_node\_role\_name) | Name of the EKS node-group role, or null if not created. |
| <a name="output_irsa_role_arn"></a> [irsa\_role\_arn](#output\_irsa\_role\_arn) | ARN of the IRSA role, or null if not created. Annotate the bound service account with this ARN. |
| <a name="output_irsa_role_name"></a> [irsa\_role\_name](#output\_irsa\_role\_name) | Name of the IRSA role, or null if not created. |
<!-- END_TF_DOCS -->
