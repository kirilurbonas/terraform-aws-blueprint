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
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.46.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
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
| <a name="input_ci_allowed_statements"></a> [ci\_allowed\_statements](#input\_ci\_allowed\_statements) | Allow-only IAM statements granted to the deployer role. Keep tightly scoped. | <pre>list(object({<br/>    sid       = optional(string)<br/>    actions   = list(string)<br/>    resources = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_ci_external_id"></a> [ci\_external\_id](#input\_ci\_external\_id) | Optional sts:ExternalId required when assuming the deployer role. | `string` | `null` | no |
| <a name="input_ci_max_session_duration"></a> [ci\_max\_session\_duration](#input\_ci\_max\_session\_duration) | Maximum session duration (seconds) for the deployer role. Range 3600 - 43200. | `number` | `3600` | no |
| <a name="input_ci_source_ip_cidrs"></a> [ci\_source\_ip\_cidrs](#input\_ci\_source\_ip\_cidrs) | Optional aws:SourceIp allow-list applied to the assume-role policy. | `list(string)` | `[]` | no |
| <a name="input_ci_trusted_principal_arns"></a> [ci\_trusted\_principal\_arns](#input\_ci\_trusted\_principal\_arns) | ARNs of IAM principals (typically a CI-account role or GitHub OIDC role) allowed to assume the deployer role. | `list(string)` | `[]` | no |
| <a name="input_create_ci_deployer_role"></a> [create\_ci\_deployer\_role](#input\_create\_ci\_deployer\_role) | Whether to create a cross-account CI/CD deployer role. | `bool` | `false` | no |
| <a name="input_create_eks_cluster_role"></a> [create\_eks\_cluster\_role](#input\_create\_eks\_cluster\_role) | Whether to create the EKS control-plane service role. | `bool` | `false` | no |
| <a name="input_create_eks_node_role"></a> [create\_eks\_node\_role](#input\_create\_eks\_node\_role) | Whether to create the EKS node-group instance role. | `bool` | `false` | no |
| <a name="input_create_irsa_role"></a> [create\_irsa\_role](#input\_create\_irsa\_role) | Whether to create an IRSA role. | `bool` | `false` | no |
| <a name="input_irsa_inline_policy_json"></a> [irsa\_inline\_policy\_json](#input\_irsa\_inline\_policy\_json) | Optional inline IAM policy JSON attached to the IRSA role. | `string` | `null` | no |
| <a name="input_irsa_managed_policy_arns"></a> [irsa\_managed\_policy\_arns](#input\_irsa\_managed\_policy\_arns) | AWS-managed policies to attach to the IRSA role. | `list(string)` | `[]` | no |
| <a name="input_irsa_namespace"></a> [irsa\_namespace](#input\_irsa\_namespace) | Kubernetes namespace of the service account that may assume this role. | `string` | `"default"` | no |
| <a name="input_irsa_oidc_provider_arn"></a> [irsa\_oidc\_provider\_arn](#input\_irsa\_oidc\_provider\_arn) | ARN of the IAM OIDC provider that backs IRSA for the target EKS cluster. | `string` | `null` | no |
| <a name="input_irsa_oidc_provider_url"></a> [irsa\_oidc\_provider\_url](#input\_irsa\_oidc\_provider\_url) | OIDC issuer URL for the target EKS cluster (e.g. https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE). | `string` | `null` | no |
| <a name="input_irsa_service_account_name"></a> [irsa\_service\_account\_name](#input\_irsa\_service\_account\_name) | Kubernetes service account name that may assume this role. | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to every role name. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to all roles. | `string` | n/a | yes |
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
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
