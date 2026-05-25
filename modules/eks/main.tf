terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
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

resource "aws_security_group_rule" "cluster_egress_all" {
  type              = "egress"
  description       = "Allow control plane to reach AWS APIs and nodes"
  security_group_id = aws_security_group.cluster.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  description              = "Allow worker nodes to talk to the API server"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
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

resource "aws_security_group_rule" "nodes_egress_all" {
  type              = "egress"
  description       = "Allow nodes to reach the internet (image pulls, AWS APIs)"
  security_group_id = aws_security_group.nodes.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "nodes_ingress_self" {
  type              = "ingress"
  description       = "Pod-to-pod traffic within the cluster"
  security_group_id = aws_security_group.nodes.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  self              = true
}

resource "aws_security_group_rule" "nodes_ingress_from_cluster" {
  type                     = "ingress"
  description              = "Kubelet & extension API server traffic from control plane"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
}

resource "aws_security_group_rule" "nodes_ingress_https_from_cluster" {
  type                     = "ingress"
  description              = "HTTPS from control plane to nodes (webhooks)"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
}

###############################################################################
# EKS Cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

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
###############################################################################

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

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
  count = var.enable_ssm_access ? 1 : 0

  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

###############################################################################
# Managed node group
###############################################################################

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  capacity_type  = var.capacity_type
  instance_types = var.instance_types
  disk_size      = var.node_disk_size_gb
  ami_type       = var.ami_type

  scaling_config {
    desired_size = var.desired_capacity
    min_size     = var.min_capacity
    max_size     = var.max_capacity
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = merge(
    {
      "capacity-type" = lower(var.capacity_type)
    },
    var.node_labels,
  )

  dynamic "taint" {
    for_each = var.node_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, {
    Name                                          = "${local.cluster_name}-ng"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

###############################################################################
# aws-auth ConfigMap (optional)
#
# When `manage_aws_auth = true`, callers must configure the kubernetes provider
# against this cluster (typically via aws_eks_cluster_auth + a provider alias).
###############################################################################

resource "kubernetes_config_map_v1_data" "aws_auth" {
  count = var.manage_aws_auth ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(concat(
      [{
        rolearn  = aws_iam_role.node.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }],
      var.aws_auth_role_map,
    ))
    mapUsers = yamlencode(var.aws_auth_user_map)
  }

  force = true

  depends_on = [aws_eks_node_group.this]
}
