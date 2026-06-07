# example: eks-cluster

Provisions a VPC plus an EKS cluster wired to it. Nodes run in private subnets;
the API endpoint is private by default.

## Usage

```bash
cd examples/eks-cluster
terraform init
terraform apply
```

To turn on the public endpoint (e.g. for kubectl from a laptop) without losing
private access:

```bash
terraform apply -var endpoint_public_access=true
```

After apply, get a kubeconfig:

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

## Approximate monthly cost

| Item | Cost (us-east-1) |
|------|------------------|
| EKS control plane | $73 |
| 3 NAT gateways (per-AZ) | ~$96 |
| 2 × t3.large nodes (on-demand) | ~$120 |
| 5 interface endpoints × 3 AZs | ~$32 |
| EBS, CloudWatch logs, NAT data | variable |
| **Total** | **~$320/mo + traffic** |

This is the cluster the README says it is — production-shaped, not a toy.
Drop `interface_endpoints = []` and `nat_gateway_mode = "single"` in your
own copy to halve the bill for a sandbox. Run `terraform destroy` when done.
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
| <a name="module_eks"></a> [eks](#module\_eks) | ../../modules/eks | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../../modules/vpc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Expose the EKS API server to the public internet. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment tag. | `string` | `"dev"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS Kubernetes version. | `string` | `"1.30"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block. | `string` | `"10.20.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | EKS API endpoint. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name. |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | OIDC issuer URL for IRSA. |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Run this to populate ~/.kube/config. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs used by the cluster. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
