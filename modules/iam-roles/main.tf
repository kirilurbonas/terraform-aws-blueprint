terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  common_tags = merge(
    {
      ManagedBy = "Terraform"
      Project   = var.project
      Module    = "terraform-aws-blueprint/iam-roles"
    },
    var.tags,
  )

  name_prefix = var.name_prefix
}

###############################################################################
# eks_cluster_role
###############################################################################

data "aws_iam_policy_document" "eks_cluster_assume" {
  count = var.create_eks_cluster_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  count = var.create_eks_cluster_role ? 1 : 0

  name_prefix        = "${local.name_prefix}-eks-cluster-"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume[0].json
  description        = "EKS control plane service role"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
    Role = "eks-cluster"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.create_eks_cluster_role ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# eks_node_role
###############################################################################

data "aws_iam_policy_document" "eks_node_assume" {
  count = var.create_eks_node_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  count = var.create_eks_node_role ? 1 : 0

  name_prefix        = "${local.name_prefix}-eks-node-"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume[0].json
  description        = "EKS managed-node-group instance role"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-role"
    Role = "eks-node"
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  count = var.create_eks_node_role ? 1 : 0

  role       = aws_iam_role.eks_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

###############################################################################
# irsa_role  (IAM Role for Service Account)
#
# Binds <namespace>/<service_account_name> in the target cluster to an IAM role
# via the cluster's OIDC provider.
###############################################################################

data "aws_iam_policy_document" "irsa_assume" {
  count = var.create_irsa_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.irsa_oidc_provider_arn]
    }

    # Scope the trust to one specific ServiceAccount in one namespace.
    condition {
      test     = "StringEquals"
      variable = "${replace(var.irsa_oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.irsa_namespace}:${var.irsa_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.irsa_oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  count = var.create_irsa_role ? 1 : 0

  name_prefix        = "${local.name_prefix}-irsa-${var.irsa_service_account_name}-"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[0].json
  description        = "IRSA role for ${var.irsa_namespace}/${var.irsa_service_account_name}"

  tags = merge(local.common_tags, {
    Name              = "${local.name_prefix}-irsa-${var.irsa_service_account_name}"
    Role              = "irsa"
    K8sNamespace      = var.irsa_namespace
    K8sServiceAccount = var.irsa_service_account_name
  })
}

resource "aws_iam_role_policy_attachment" "irsa_managed" {
  for_each = var.create_irsa_role ? toset(var.irsa_managed_policy_arns) : toset([])

  role       = aws_iam_role.irsa[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "irsa_inline" {
  count = var.create_irsa_role && var.irsa_inline_policy_json != null ? 1 : 0

  name   = "inline"
  role   = aws_iam_role.irsa[0].id
  policy = var.irsa_inline_policy_json
}

###############################################################################
# ci_deployer_role
#
# Cross-account assumable role used by external CI/CD systems (e.g. a CI account
# or a GitHub OIDC provider). Permissions are limited to caller-supplied
# (actions, resources) pairs.
###############################################################################

data "aws_iam_policy_document" "ci_assume" {
  count = var.create_ci_deployer_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.ci_trusted_principal_arns
    }

    dynamic "condition" {
      for_each = var.ci_external_id != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.ci_external_id]
      }
    }

    dynamic "condition" {
      for_each = length(var.ci_source_ip_cidrs) > 0 ? [1] : []
      content {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = var.ci_source_ip_cidrs
      }
    }
  }
}

data "aws_iam_policy_document" "ci_permissions" {
  count = var.create_ci_deployer_role ? 1 : 0

  dynamic "statement" {
    for_each = var.ci_allowed_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "ci_deployer" {
  count = var.create_ci_deployer_role ? 1 : 0

  name_prefix          = "${local.name_prefix}-ci-deployer-"
  assume_role_policy   = data.aws_iam_policy_document.ci_assume[0].json
  max_session_duration = var.ci_max_session_duration
  description          = "Cross-account CI/CD deployer role"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ci-deployer-role"
    Role = "ci-deployer"
  })
}

resource "aws_iam_role_policy" "ci_deployer" {
  count = var.create_ci_deployer_role ? 1 : 0

  name   = "permissions"
  role   = aws_iam_role.ci_deployer[0].id
  policy = data.aws_iam_policy_document.ci_permissions[0].json
}
