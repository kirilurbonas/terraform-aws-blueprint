# eks

Production EKS cluster with multiple managed node groups (each backed by a
launch template that enforces IMDSv2), managed add-ons, EKS Pod Identity
associations and/or an OIDC provider for IRSA, KMS envelope encryption of secrets, full control-plane logging, and
authentication via Access Entries (no `aws-auth` ConfigMap, no `kubernetes`
provider dependency).

## Features

- EKS control plane with configurable Kubernetes version
- Private API endpoint by default; public access is opt-in and CIDR-scoped
- KMS envelope encryption of Kubernetes secrets (module-managed key unless one
  is supplied)
- All five control-plane log streams shipped to CloudWatch
- OIDC provider provisioned with a pinned Amazon Root CA 1 thumbprint (no
  `tls` provider, no fragile plan-time HTTPS dial); can be switched off with
  `create_oidc_provider = false`
- **EKS Pod Identity** associations via a `pod_identity_associations` map
- Optional `upgrade_policy` (STANDARD / EXTENDED support) and ARC
  `zonal_shift_config`
- **Multiple managed node groups** via a `node_groups` map (mix ON_DEMAND /
  SPOT, instance families, taints, labels per group)
- **Launch-template-based nodes**: IMDSv2 required, root EBS encrypted,
  detailed monitoring, instance + volume tag specifications
- **Managed add-ons** (`vpc-cni`, `coredns`, `kube-proxy`,
  `aws-ebs-csi-driver`, `eks-pod-identity-agent`, ...) declared via the
  `cluster_addons` map, with per-add-on `service_account_role_arn` and
  `configuration_values`
- **Access Entries** (`authentication_mode = "API"`) — IAM principals are
  mapped to Kubernetes RBAC through the IAM API; no chicken-and-egg with the
  legacy `aws-auth` ConfigMap
- Least-privilege security groups with v5 `aws_vpc_security_group_*_rule`
  resources (tagged individually)

## Usage

```hcl
module "eks" {
  source = "github.com/kirilurbonas/terraform-aws-blueprint//modules/eks?ref=v0.2.0"

  name_prefix        = "platform"
  environment        = "prod"
  project            = "blueprint"
  kubernetes_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access = false

  node_groups = {
    system = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m6i.large"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      taints = [
        { key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" },
      ]
    }
    apps = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]
      desired_size   = 3
      min_size       = 3
      max_size       = 12
    }
  }

  cluster_addons = {
    vpc-cni    = {}
    coredns    = {}
    kube-proxy = {}
  }

  access_entries = {
    platform_admin = {
      principal_arn = "arn:aws:iam::111122223333:role/platform-admin"
      policy_associations = [
        {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        },
      ]
    }
  }
}
```

### Access Entries

The module sets `authentication_mode = "API"` by default — `aws-auth` is gone.
Operators are granted access via the `access_entries` map; each entry can carry
zero or more `policy_associations` referencing AWS-managed cluster-access
policies (`AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`,
`AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`) scoped to the whole cluster or
specific namespaces.

The node IAM role is mapped automatically via a dedicated `EC2_LINUX` entry —
no caller action required.

### Pod Identity vs IRSA

Both mechanisms give a Kubernetes service account an IAM role. They can run
side by side on the same cluster.

| | EKS Pod Identity | IRSA |
|---|---|---|
| Module input | `pod_identity_associations` | `create_oidc_provider` (default `true`) |
| Per-cluster IAM resource | none | IAM OIDC provider |
| Role trust policy | `pods.eks.amazonaws.com` (`sts:AssumeRole`, `sts:TagSession`) | the cluster's OIDC provider, scoped by `sub` claim |
| Service account annotation | not needed | `eks.amazonaws.com/role-arn` |
| Requires | `eks-pod-identity-agent` add-on | nothing extra in-cluster |

Pod Identity is the AWS-recommended pattern for new workloads: the same role
can be reused across clusters without editing its trust policy. Some add-ons
and tools still only support IRSA, which is why the OIDC provider stays on by
default.

```hcl
module "eks" {
  # ...

  cluster_addons = {
    vpc-cni                = {}
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver = {
      # Add-ons take an IRSA role directly.
      service_account_role_arn = aws_iam_role.ebs_csi.arn
      configuration_values     = jsonencode({ controller = { replicaCount = 2 } })
    }
  }

  pod_identity_associations = {
    external_dns = {
      namespace       = "kube-system"
      service_account = "external-dns"
      role_arn        = aws_iam_role.external_dns.arn
    }
  }

  # Only once nothing on the cluster uses IRSA any more.
  # create_oidc_provider = false
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
```

Setting `create_oidc_provider = false` on an existing cluster destroys the IAM
OIDC provider and breaks every IRSA role that trusts it. Migrate those
workloads to Pod Identity first. `oidc_provider_arn` is `null` while the
provider is disabled; `cluster_oidc_issuer_url` is a cluster attribute and is
always populated.

Upgrading from v0.3.x needs no state surgery: a `moved` block migrates
`aws_iam_openid_connect_provider.this` to `aws_iam_openid_connect_provider.this[0]`.

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
| `oidc_thumbprint_list` | `list(string)` | Amazon Root CA 1 | no | OIDC thumbprints. |
| `create_oidc_provider` | `bool` | `true` | no | Create the IAM OIDC provider for IRSA. |
| `upgrade_policy` | `object` | `null` | no | `{ support_type = "STANDARD" \| "EXTENDED" }`. `null` = AWS default. |
| `zonal_shift_config` | `object` | `null` | no | `{ enabled = bool }`. `null` = AWS default (off). |
| `authentication_mode` | `string` | `"API"` | no | `API` or `API_AND_CONFIG_MAP`. |
| `bootstrap_cluster_creator_admin_permissions` | `bool` | `true` | no | Grant the apply-time IAM principal cluster-admin. |
| `access_entries` | `map(object)` | `{}` | no | IAM → Kubernetes RBAC mappings + optional policy associations. |
| `node_groups` | `map(object)` | — | yes | Managed node groups keyed by short name. See below. |
| `cluster_addons` | `map(object)` | `{}` | no | Managed add-ons keyed by add-on name. |
| `pod_identity_associations` | `map(object)` | `{}` | no | `{ namespace, service_account, role_arn }` per association. |
| `tags` | `map(string)` | `{}` | no | Extra resource tags. |

### `node_groups` entry shape

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `capacity_type` | `string` | `"ON_DEMAND"` | `ON_DEMAND` or `SPOT`. |
| `instance_types` | `list(string)` | `["t3.large"]` | Multiple recommended for SPOT diversification. |
| `ami_type` | `string` | `"AL2023_x86_64_STANDARD"` | Node AMI family. |
| `disk_size_gb` | `number` | `50` | Root EBS size (encrypted). |
| `desired_size` / `min_size` / `max_size` | `number` | `2` / `1` / `5` | Scaling bounds. |
| `labels` | `map(string)` | `{}` | Extra k8s labels. |
| `taints` | `list(object)` | `[]` | k8s taints (`{ key, value, effect }`). |
| `enable_ssm_access` | `bool` | `true` | Attach SSM policy. |
| `max_unavailable_pc` | `number` | `33` | Rolling-update max-unavailable percent. |

### `cluster_addons` entry shape

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | `string` | `null` (latest) | Add-on version. |
| `resolve_conflicts_on_create` | `string` | `"OVERWRITE"` | `NONE` / `OVERWRITE`. |
| `resolve_conflicts_on_update` | `string` | `"OVERWRITE"` | `NONE` / `OVERWRITE` / `PRESERVE`. |
| `service_account_role_arn` | `string` | `null` | IRSA role for the add-on (IAM role ARN). |
| `configuration_values` | `string` | `null` | JSON (or YAML) object, e.g. `jsonencode({...})`. |

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
| `oidc_provider_arn` | IAM OIDC provider ARN (`null` when `create_oidc_provider = false`). |
| `node_groups` | `{ <name> = { arn, status } }` for every managed node group. |
| `node_iam_role_arn` | Node IAM role ARN. |
| `node_security_group_id` | Node SG ID. |
| `kms_key_arn` | KMS key used for secrets encryption. |
| `addon_versions` | Map of installed add-on → resolved version. |
| `pod_identity_associations` | `{ <key> = { association_arn, association_id } }`. |
| `kubeconfig_command` | Shell command to update kubeconfig. |

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
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eks_access_entry.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_entry.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_eks_pod_identity_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster_amazoneksclusterpolicy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_worker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.cluster_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.nodes_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nodes_kubelet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nodes_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.nodes_webhooks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.cluster_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment (dev, staging, prod). | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS control plane Kubernetes version (e.g. "1.30"). | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix applied to all named resources. | `string` | n/a | yes |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Map of managed node groups, keyed by short name (e.g. system, apps, gpu). Mix ON\_DEMAND/SPOT, instance families, and taints per group. | <pre>map(object({<br/>    capacity_type  = optional(string, "ON_DEMAND")<br/>    instance_types = optional(list(string), ["t3.large"])<br/>    ami_type       = optional(string, "AL2023_x86_64_STANDARD")<br/>    disk_size_gb   = optional(number, 50)<br/>    desired_size   = optional(number, 2)<br/>    min_size       = optional(number, 1)<br/>    max_size       = optional(number, 5)<br/>    labels         = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>    enable_ssm_access  = optional(bool, true)<br/>    max_unavailable_pc = optional(number, 33)<br/>  }))</pre> | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project tag applied to every resource. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for cluster ENIs and node groups. Use private subnets in production. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID the cluster lives in. | `string` | n/a | yes |
| <a name="input_access_entries"></a> [access\_entries](#input\_access\_entries) | Access entries to create on the cluster, keyed by a stable name. Each may include policy associations (e.g. AmazonEKSClusterAdminPolicy scoped to cluster, AmazonEKSAdminPolicy scoped to a namespace). | <pre>map(object({<br/>    principal_arn     = string<br/>    type              = optional(string, "STANDARD")<br/>    kubernetes_groups = optional(list(string))<br/>    user_name         = optional(string)<br/>    policy_associations = optional(list(object({<br/>      policy_arn = string<br/>      access_scope = object({<br/>        type       = string<br/>        namespaces = optional(list(string))<br/>      })<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | Authentication mode for the cluster. API uses access entries only; API\_AND\_CONFIG\_MAP keeps aws-auth around as well. | `string` | `"API"` | no |
| <a name="input_bootstrap_cluster_creator_admin_permissions"></a> [bootstrap\_cluster\_creator\_admin\_permissions](#input\_bootstrap\_cluster\_creator\_admin\_permissions) | Whether the IAM principal that runs terraform apply gets a built-in cluster-admin access entry. | `bool` | `true` | no |
| <a name="input_cluster_addons"></a> [cluster\_addons](#input\_cluster\_addons) | Managed EKS add-ons, keyed by add-on name (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, eks-pod-identity-agent, ...). Empty = none. Versions default to latest compatible when omitted. service\_account\_role\_arn sets an IRSA role for the add-on; configuration\_values takes a JSON (or YAML) object matching the add-on's configuration schema. | <pre>map(object({<br/>    version                     = optional(string)<br/>    resolve_conflicts_on_create = optional(string, "OVERWRITE")<br/>    resolve_conflicts_on_update = optional(string, "OVERWRITE")<br/>    service_account_role_arn    = optional(string)<br/>    configuration_values        = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_create_oidc_provider"></a> [create\_oidc\_provider](#input\_create\_oidc\_provider) | Whether to create the IAM OIDC provider used by IRSA. Set to false when every workload uses EKS Pod Identity, or when the provider is managed elsewhere; oidc\_provider\_arn is then null. | `bool` | `true` | no |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | Control plane log streams to ship to CloudWatch. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Whether the cluster API server is reachable from the public internet. | `bool` | `false` | no |
| <a name="input_endpoint_public_access_cidrs"></a> [endpoint\_public\_access\_cidrs](#input\_endpoint\_public\_access\_cidrs) | CIDR blocks permitted on the public endpoint. Ignored when endpoint\_public\_access = false. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Optional KMS key ARN for secrets envelope encryption. If null, a key is created. | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log group retention for cluster logs. | `number` | `90` | no |
| <a name="input_oidc_thumbprint_list"></a> [oidc\_thumbprint\_list](#input\_oidc\_thumbprint\_list) | Thumbprints for the IAM OIDC provider. Default is the Amazon Root CA 1 thumbprint that backs every public EKS issuer. | `list(string)` | <pre>[<br/>  "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"<br/>]</pre> | no |
| <a name="input_pod_identity_associations"></a> [pod\_identity\_associations](#input\_pod\_identity\_associations) | EKS Pod Identity associations, keyed by a stable name. Each binds a Kubernetes service account to an IAM role. Requires the eks-pod-identity-agent add-on (see cluster\_addons). | <pre>map(object({<br/>    namespace       = string<br/>    service_account = string<br/>    role_arn        = string<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every resource. | `map(string)` | `{}` | no |
| <a name="input_upgrade_policy"></a> [upgrade\_policy](#input\_upgrade\_policy) | Cluster upgrade policy. support\_type is STANDARD or EXTENDED. null leaves the AWS default (EXTENDED) in place. | <pre>object({<br/>    support_type = string<br/>  })</pre> | `null` | no |
| <a name="input_zonal_shift_config"></a> [zonal\_shift\_config](#input\_zonal\_shift\_config) | ARC zonal shift configuration for the cluster. null leaves the AWS default (disabled) in place. | <pre>object({<br/>    enabled = bool<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addon_versions"></a> [addon\_versions](#output\_addon\_versions) | Map of installed add-on name -> resolved version. |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the EKS cluster. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64-encoded cluster CA certificate. Decode and pass to the kubernetes provider. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Kubernetes API server endpoint. |
| <a name="output_cluster_iam_role_arn"></a> [cluster\_iam\_role\_arn](#output\_cluster\_iam\_role\_arn) | ARN of the IAM role assumed by the EKS control plane. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_oidc_issuer_url"></a> [cluster\_oidc\_issuer\_url](#output\_cluster\_oidc\_issuer\_url) | OIDC issuer URL used for IRSA trust policies. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | Security group ID attached to the cluster control plane ENIs. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | Kubernetes version running on the control plane. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | KMS key ARN used for secrets envelope encryption. |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | Shell command that writes a kubeconfig entry for this cluster. |
| <a name="output_node_groups"></a> [node\_groups](#output\_node\_groups) | Map of node group name -> { arn, status } for every managed node group. |
| <a name="output_node_iam_role_arn"></a> [node\_iam\_role\_arn](#output\_node\_iam\_role\_arn) | ARN of the IAM role assumed by worker nodes. Use this in access entries and IRSA trust policies that need to recognize node identity. |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | Security group ID attached to worker nodes. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC provider that backs IRSA for this cluster. null when create\_oidc\_provider = false. |
| <a name="output_pod_identity_associations"></a> [pod\_identity\_associations](#output\_pod\_identity\_associations) | Map of pod identity association key -> { association\_arn, association\_id }. |
<!-- END_TF_DOCS -->
