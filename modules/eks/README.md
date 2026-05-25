# eks

Production EKS cluster with multiple managed node groups (each backed by a
launch template that enforces IMDSv2), managed add-ons, OIDC provider for
IRSA, KMS envelope encryption of secrets, full control-plane logging, and
authentication via Access Entries (no `aws-auth` ConfigMap, no `kubernetes`
provider dependency).

## Features

- EKS control plane with configurable Kubernetes version
- Private API endpoint by default; public access is opt-in and CIDR-scoped
- KMS envelope encryption of Kubernetes secrets (module-managed key unless one
  is supplied)
- All five control-plane log streams shipped to CloudWatch
- OIDC provider provisioned with a pinned Amazon Root CA 1 thumbprint (no
  `tls` provider, no fragile plan-time HTTPS dial)
- **Multiple managed node groups** via a `node_groups` map (mix ON_DEMAND /
  SPOT, instance families, taints, labels per group)
- **Launch-template-based nodes**: IMDSv2 required, root EBS encrypted,
  detailed monitoring, instance + volume tag specifications
- **Managed add-ons** (`vpc-cni`, `coredns`, `kube-proxy`,
  `aws-ebs-csi-driver`, ...) declared via the `cluster_addons` map
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
| `authentication_mode` | `string` | `"API"` | no | `API` or `API_AND_CONFIG_MAP`. |
| `bootstrap_cluster_creator_admin_permissions` | `bool` | `true` | no | Grant the apply-time IAM principal cluster-admin. |
| `access_entries` | `map(object)` | `{}` | no | IAM → Kubernetes RBAC mappings + optional policy associations. |
| `node_groups` | `map(object)` | — | yes | Managed node groups keyed by short name. See below. |
| `cluster_addons` | `map(object)` | `{}` | no | Managed add-ons keyed by add-on name. |
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
| `service_account_role_arn` | `string` | `null` | IRSA role for the add-on. |
| `configuration_values` | `string` | `null` | JSON or YAML config. |

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
| `node_groups` | `{ <name> = { arn, status } }` for every managed node group. |
| `node_iam_role_arn` | Node IAM role ARN. |
| `node_security_group_id` | Node SG ID. |
| `kms_key_arn` | KMS key used for secrets encryption. |
| `addon_versions` | Map of installed add-on → resolved version. |
| `kubeconfig_command` | Shell command to update kubeconfig. |

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs auto-generates the full requirements / providers / resources / inputs / outputs tables here when the pre-commit hook runs. The hand-written inputs/outputs tables above stay; this block is appended below them. -->
<!-- END_TF_DOCS -->
