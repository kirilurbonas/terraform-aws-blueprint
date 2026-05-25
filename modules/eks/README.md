# eks

Production EKS cluster with managed node group, OIDC provider for IRSA, KMS
envelope encryption of secrets, and full control-plane logging.

## Features

- EKS control plane with configurable Kubernetes version
- Private API endpoint by default; public access is opt-in and CIDR-scoped
- KMS-backed envelope encryption of Kubernetes secrets (key is module-managed
  unless one is supplied)
- All five control-plane log streams shipped to CloudWatch
- OIDC provider provisioned automatically for IRSA workloads
- Managed node group supporting `ON_DEMAND` and `SPOT`
- Node IAM role with the three required AWS managed policies plus optional
  SSM Session Manager access
- Least-privilege security groups: nodes can reach AWS APIs; control plane and
  nodes are wired together with only the ports the EKS data plane needs
- Optional management of the `aws-auth` ConfigMap

## Usage

```hcl
module "eks" {
  source = "github.com/your-org/terraform-aws-blueprint//modules/eks?ref=v1.0.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  kubernetes_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  capacity_type    = "ON_DEMAND"
  instance_types   = ["m6i.large", "m6a.large"]
  desired_capacity = 3
  min_capacity     = 3
  max_capacity     = 10

  endpoint_public_access = false
}
```

### aws-auth ConfigMap

When `manage_aws_auth = true` you must configure the `kubernetes` provider
against the new cluster (typically via `aws_eks_cluster_auth` + a provider
alias). Otherwise `terraform apply` will fail when it tries to talk to the API
server. The node role is mapped automatically; pass operator/CI roles via
`aws_auth_role_map`.

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name_prefix` | `string` | — | yes | Prefix on every named resource. |
| `environment` | `string` | — | yes | `dev`, `staging`, or `prod`. |
| `project` | `string` | — | yes | Project tag. |
| `kubernetes_version` | `string` | — | yes | e.g. `"1.30"`. |
| `vpc_id` | `string` | — | yes | VPC the cluster lives in. |
| `subnet_ids` | `list(string)` | — | yes | At least 2 subnets, usually private. |
| `endpoint_public_access` | `bool` | `false` | no | Expose API publicly. |
| `endpoint_public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | no | CIDRs allowed on public endpoint. |
| `enabled_cluster_log_types` | `list(string)` | all five | no | Control-plane log streams. |
| `log_retention_days` | `number` | `90` | no | CloudWatch retention. |
| `kms_key_arn` | `string` | `null` | no | Pre-existing KMS key for secrets. |
| `capacity_type` | `string` | `"ON_DEMAND"` | no | `ON_DEMAND` or `SPOT`. |
| `instance_types` | `list(string)` | `["t3.large"]` | no | EC2 instance types. |
| `ami_type` | `string` | `"AL2023_x86_64_STANDARD"` | no | Node AMI family. |
| `node_disk_size_gb` | `number` | `50` | no | Node root EBS size. |
| `desired_capacity` | `number` | `2` | no | Initial node count. |
| `min_capacity` | `number` | `1` | no | Min nodes. |
| `max_capacity` | `number` | `5` | no | Max nodes. |
| `node_labels` | `map(string)` | `{}` | no | Extra k8s labels. |
| `node_taints` | `list(object)` | `[]` | no | k8s taints applied to nodes. |
| `enable_ssm_access` | `bool` | `true` | no | Attach SSM policy for Session Manager. |
| `manage_aws_auth` | `bool` | `false` | no | Module manages the aws-auth CM. |
| `aws_auth_role_map` | `list(object)` | `[]` | no | Extra IAM roles mapped into RBAC. |
| `aws_auth_user_map` | `list(object)` | `[]` | no | IAM users mapped into RBAC. |
| `tags` | `map(string)` | `{}` | no | Extra resource tags. |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name. |
| `cluster_arn` | EKS cluster ARN. |
| `cluster_endpoint` | API server endpoint. |
| `cluster_version` | Running Kubernetes version. |
| `cluster_ca_certificate` | Base64-encoded cluster CA. |
| `cluster_security_group_id` | Control-plane SG ID. |
| `cluster_iam_role_arn` | Control-plane IAM role ARN. |
| `cluster_oidc_issuer_url` | OIDC issuer URL for IRSA. |
| `oidc_provider_arn` | IAM OIDC provider ARN. |
| `node_group_arn` | Managed node group ARN. |
| `node_group_name` | Managed node group name. |
| `node_iam_role_arn` | Node IAM role ARN. |
| `node_security_group_id` | Node SG ID. |
| `kms_key_arn` | KMS key used for secrets encryption. |
| `kubeconfig_command` | Shell command to update kubeconfig. |
