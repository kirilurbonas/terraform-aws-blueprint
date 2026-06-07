terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project
      Module      = "terraform-aws-blueprint/eks"
    },
    var.tags,
  )

  name_prefix  = "${var.name_prefix}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"
  enable_node_ssm = anytrue([
    for ng in values(local.node_groups) : ng.enable_ssm_access
  ])

  # Build a normalized map of node groups so we can for_each over it deterministically.
  node_groups = {
    for k, ng in var.node_groups : k => merge({
      capacity_type      = "ON_DEMAND"
      instance_types     = ["t3.large"]
      ami_type           = "AL2023_x86_64_STANDARD"
      disk_size_gb       = 50
      desired_size       = 2
      min_size           = 1
      max_size           = 5
      labels             = {}
      taints             = []
      enable_ssm_access  = true
      max_unavailable_pc = 33
    }, ng)
  }
}

###############################################################################
# Cluster IAM role
###############################################################################

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name_prefix        = "${local.name_prefix}-eks-cluster-"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_amazoneksclusterpolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# Cluster security group
###############################################################################

resource "aws_security_group" "cluster" {
  name_prefix = "${local.name_prefix}-eks-cluster-"
  description = "EKS cluster control-plane security group for ${local.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow control plane to reach AWS APIs and nodes"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-egress-all"
  })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Allow worker nodes to talk to the API server"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-ingress-nodes"
  })
}

###############################################################################
# Node security group
###############################################################################

resource "aws_security_group" "nodes" {
  name_prefix = "${local.name_prefix}-eks-nodes-"
  description = "EKS worker node security group for ${local.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name                                          = "${local.name_prefix}-eks-nodes-sg"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Allow nodes to reach the internet (image pulls, AWS APIs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-nodes-egress-all"
  })
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Pod-to-pod traffic within the cluster"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-nodes-ingress-self"
  })
}

resource "aws_vpc_security_group_ingress_rule" "nodes_kubelet" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Kubelet & extension API server traffic from control plane"
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-nodes-ingress-kubelet"
  })
}

resource "aws_vpc_security_group_ingress_rule" "nodes_webhooks" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "HTTPS from control plane to nodes (webhooks)"
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-nodes-ingress-webhooks"
  })
}

###############################################################################
# EKS Cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # Access Entries replace the legacy aws-auth ConfigMap.
  # API_AND_CONFIG_MAP keeps the door open for in-cluster bootstrap aws-auth
  # entries that some Helm charts still write; flip to API once you're sure
  # nothing else writes to aws-auth.
  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  encryption_config {
    provider {
      key_arn = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.eks[0].arn
    }
    resources = ["secrets"]
  }

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_amazoneksclusterpolicy,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-logs"
  })
}

###############################################################################
# KMS for envelope encryption of secrets
###############################################################################

resource "aws_kms_key" "eks" {
  count = var.kms_key_arn == null ? 1 : 0

  description             = "EKS envelope encryption key for ${local.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-kms"
  })
}

resource "aws_kms_alias" "eks" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/${local.cluster_name}"
  target_key_id = aws_kms_key.eks[0].key_id
}

###############################################################################
# OIDC provider for IRSA
#
# AWS publishes a stable Amazon Root CA thumbprint that EKS uses for every
# cluster. We pin it as a literal here instead of dialling the issuer with the
# tls provider at plan time (which is fragile for private clusters and
# triggers replacements on cert rotation).
###############################################################################

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprint_list

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc"
  })
}

###############################################################################
# Node group IAM role
###############################################################################

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix        = "${local.name_prefix}-eks-node-"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  count = local.enable_node_ssm ? 1 : 0

  # The node role is shared across every managed node group, so the SSM policy
  # should only be attached once even if multiple groups request SSM access.
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

###############################################################################
# Node launch template — pins IMDSv2 and tags every node ENI / volume
###############################################################################

resource "aws_launch_template" "node" {
  for_each = local.node_groups

  name_prefix            = "${local.cluster_name}-${each.key}-"
  description            = "Launch template for EKS node group ${each.key}"
  update_default_version = true

  vpc_security_group_ids = [aws_security_group.nodes.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # 2 hops so pods using IRSA can still reach IMDS via the host
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name}-${each.key}-node"
      NodeGroup = each.key
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name}-${each.key}-vol"
      NodeGroup = each.key
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${each.key}-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Managed node groups
###############################################################################

resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-${each.key}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable_percentage = each.value.max_unavailable_pc
  }

  labels = merge(
    {
      "capacity-type" = lower(each.value.capacity_type)
      "node-group"    = each.key
    },
    each.value.labels,
  )

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, {
    Name                                          = "${local.cluster_name}-${each.key}"
    NodeGroup                                     = each.key
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    # Let Cluster Autoscaler / Karpenter own desired_size at runtime.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

###############################################################################
# Managed cluster add-ons
###############################################################################

resource "aws_eks_addon" "this" {
  for_each = var.cluster_addons

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = lookup(each.value, "version", null)
  resolve_conflicts_on_create = lookup(each.value, "resolve_conflicts_on_create", "OVERWRITE")
  resolve_conflicts_on_update = lookup(each.value, "resolve_conflicts_on_update", "OVERWRITE")
  service_account_role_arn    = lookup(each.value, "service_account_role_arn", null)
  configuration_values        = lookup(each.value, "configuration_values", null)

  tags = merge(local.common_tags, {
    Name  = "${local.cluster_name}-addon-${each.key}"
    Addon = each.key
  })

  # Addons that schedule on nodes (vpc-cni excepted) need a node group ready.
  depends_on = [aws_eks_node_group.this]
}

###############################################################################
# Access Entries — replaces the aws-auth ConfigMap
###############################################################################

# Always grant the node role node permissions via the dedicated EC2-Linux entry
# type. This avoids the chicken-and-egg of the legacy ConfigMap.
resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-access-node"
  })
}

resource "aws_eks_access_entry" "extra" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = lookup(each.value, "type", "STANDARD")
  kubernetes_groups = lookup(each.value, "kubernetes_groups", null)
  user_name         = lookup(each.value, "user_name", null)

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-access-${each.key}"
  })
}

resource "aws_eks_access_policy_association" "extra" {
  for_each = {
    for pair in flatten([
      for k, entry in var.access_entries : [
        for p in lookup(entry, "policy_associations", []) : {
          key           = "${k}:${p.policy_arn}"
          entry_key     = k
          policy_arn    = p.policy_arn
          access_scope  = p.access_scope
          principal_arn = entry.principal_arn
        }
      ]
    ]) : pair.key => pair
  }

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope.type
    namespaces = lookup(each.value.access_scope, "namespaces", null)
  }

  depends_on = [aws_eks_access_entry.extra]
}
