# example: full-stack

End-to-end reference deployment that ties every blueprint module together:

```
            ┌────────────────────────────────────────────────┐
            │                      VPC                       │
            │  3 AZ • per-AZ NAT • Flow Logs to S3           │
            └───────┬──────────────────┬────────────┬────────┘
                    │ private subnets  │            │ private subnets
                    ▼                  ▼            ▼
            ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
            │     EKS      │   │     RDS      │  │  S3 secure   │
            │  control     │   │ postgres 16  │  │  artifacts   │
            │  + nodes     │   │   multi-AZ   │  │  bucket      │
            └──────┬───────┘   └──────────────┘  └──────┬───────┘
                   │ OIDC                                ▲
                   ▼                                     │
            ┌──────────────────────────────────────────────┐
            │ IRSA role → ServiceAccount app/app           │
            │  s3:Get/Put/Delete on the artifacts bucket   │
            └──────────────────────────────────────────────┘
```

Wiring highlights:

- EKS nodes live in the VPC's private subnets.
- RDS lives in the same private subnets; its security group only permits the
  EKS node security group on the Postgres port.
- A secure S3 bucket holds application artifacts.
- An IRSA role binds the `app/app` Kubernetes ServiceAccount to scoped
  read/write permissions on the artifacts bucket — no static keys, no
  node-wide IAM access.

## Usage

```bash
cd examples/full-stack
terraform init
terraform apply
```

After apply:

```bash
$(terraform output -raw kubeconfig_command)

# Annotate the application ServiceAccount so it gets AWS credentials:
kubectl create namespace app
kubectl create sa app -n app
kubectl annotate sa app -n app \
  "eks.amazonaws.com/role-arn=$(terraform output -raw app_irsa_role_arn)"
```

The RDS master password is in Secrets Manager — read the ARN from
`rds_master_secret_arn` and fetch it from the application via
`secretsmanager:GetSecretValue` (grant via a second IRSA binding when needed).

## Approximate monthly cost

| Item | Cost (us-east-1) |
|------|------------------|
| EKS control plane | $73 |
| 3 NAT gateways (per-AZ) | ~$96 |
| 2 × m6i.large system nodes (on-demand) | ~$140 |
| 3 × m6i.large apps nodes (spot) | ~$70 |
| RDS Postgres db.m6i.large (Multi-AZ) | ~$420 |
| RDS read replica db.m6i.large | ~$210 |
| 5 interface endpoints × 3 AZs | ~$32 |
| KMS, S3, Secrets Manager, EBS, logs | ~$20 |
| **Total** | **~$1060/mo + traffic** |

This is the **reference deployment** for what a production stack looks like.
For an iterative dev environment, drop the read replica, switch RDS to
`multi_az = false`, scale node groups down, and set `nat_gateway_mode =
"single"`. Run `terraform destroy` when done.
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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_app_kms"></a> [app\_kms](#module\_app\_kms) | ../../modules/kms | n/a |
| <a name="module_artifacts_bucket"></a> [artifacts\_bucket](#module\_artifacts\_bucket) | ../../modules/s3-secure | n/a |
| <a name="module_eks"></a> [eks](#module\_eks) | ../../modules/eks | n/a |
| <a name="module_platform_roles"></a> [platform\_roles](#module\_platform\_roles) | ../../modules/iam-roles | n/a |
| <a name="module_rds"></a> [rds](#module\_rds) | ../../modules/rds | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../../modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_iam_policy_document.app_artifacts_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_namespace"></a> [app\_namespace](#input\_app\_namespace) | Kubernetes namespace of the application service account that gets IRSA bound to the artifacts bucket. | `string` | `"app"` | no |
| <a name="input_app_service_account"></a> [app\_service\_account](#input\_app\_service\_account) | Kubernetes service account name that gets IRSA bound to the artifacts bucket. | `string` | `"app"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev / staging / prod). | `string` | `"dev"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS Kubernetes version. | `string` | `"1.30"` | no |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | `"blueprint"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block. | `string` | `"10.30.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_irsa_role_arn"></a> [app\_irsa\_role\_arn](#output\_app\_irsa\_role\_arn) | Role ARN to put in the application's ServiceAccount annotation: eks.amazonaws.com/role-arn. |
| <a name="output_artifacts_bucket_arn"></a> [artifacts\_bucket\_arn](#output\_artifacts\_bucket\_arn) | ARN of the artifacts bucket. |
| <a name="output_artifacts_bucket_name"></a> [artifacts\_bucket\_name](#output\_artifacts\_bucket\_name) | Name of the artifacts bucket. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | EKS API endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name. |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | OIDC issuer URL for IRSA. |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Shell command to update ~/.kube/config. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs. |
| <a name="output_rds_endpoint"></a> [rds\_endpoint](#output\_rds\_endpoint) | RDS endpoint (host:port). |
| <a name="output_rds_master_secret_arn"></a> [rds\_master\_secret\_arn](#output\_rds\_master\_secret\_arn) | Secrets Manager ARN for the RDS master credentials. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
